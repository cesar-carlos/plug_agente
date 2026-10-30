import 'dart:async';

import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_control.dart';
import 'package:result_dart/result_dart.dart';

/// Registers ownership before asynchronous process creation, including shutdown
/// races. Durable admission/deduplication remain the journal's responsibility.
final class ActionIoSessionSupervisor {
  ActionIoSessionSupervisor({IActionIoMetrics? metrics}) : _metrics = metrics {
    _publishMetrics();
  }

  final IActionIoMetrics? _metrics;
  final Map<String, _OwnedSession> _sessions = {};
  final Map<String, _OwnedLaunch> _launches = {};
  final List<Exception> _cleanupFailures = [];
  bool _accepting = true;
  String? _maintenanceOperation;
  Future<Result<Unit>>? _shutdown;

  bool get accepting => _accepting && _maintenanceOperation == null && _cleanupFailures.isEmpty;
  int get activeCount => _sessions.length;
  bool get isSafelyIdle => _sessions.isEmpty && _launches.isEmpty && _cleanupFailures.isEmpty;

  /// Owns asynchronous admission/queue work before the first await. Completion
  /// must confirm both native cleanup and all pending journal writes.
  Result<Unit> launch(
    String executionId, {
    required Future<Result<Unit>> Function() execute,
    required Future<Result<Unit>> Function() cancelPending,
  }) {
    if (!accepting || _launches.containsKey(executionId) || _sessions.containsKey(executionId)) {
      return Failure(_failure('ACTION_IO_ADMISSION_CLOSED'));
    }
    final owned = _OwnedLaunch(cancelPending);
    _launches[executionId] = owned;
    _publishMetrics();
    unawaited(_observeLaunch(executionId, owned, execute));
    return const Success(unit);
  }

  Future<void> _observeLaunch(String id, _OwnedLaunch owned, Future<Result<Unit>> Function() execute) async {
    try {
      final result = await execute();
      if (result.isError()) _recordCleanupFailure(result.exceptionOrNull()!);
    } on Object {
      _recordCleanupFailure(_failure('ACTION_IO_LAUNCH_COMPLETION_UNKNOWN'));
    } finally {
      _launches.remove(id);
      _publishMetrics();
      owned.done.complete();
    }
  }

  /// Requests cancellation without claiming that native termination completed.
  /// The caller must authorize the execution owner before invoking this method.
  Result<bool> requestCancel(String executionId) {
    final owned = _sessions[executionId];
    if (owned == null) return const Success(false);
    owned.cancelRequested = true;
    final session = owned.session;
    if (session != null) unawaited(_stopOwned(owned, session));
    return const Success(true);
  }

  Future<Result<Unit>> _stopOwned(_OwnedSession owned, IActionIoSessionControl session) =>
      owned.stopping ??= _stop(session);

  Result<Unit> pauseForMaintenance(String operation) {
    if (!_accepting || operation.isEmpty || (_maintenanceOperation != null && _maintenanceOperation != operation)) {
      return Failure(_failure('ACTION_IO_ADMISSION_CLOSED'));
    }
    _maintenanceOperation = operation;
    return const Success(unit);
  }

  Result<Unit> resumeAfterMaintenance(String operation) {
    if (!_accepting || _maintenanceOperation != operation || _cleanupFailures.isNotEmpty) {
      return Failure(_failure('ACTION_IO_ADMISSION_CLOSED'));
    }
    _maintenanceOperation = null;
    return const Success(unit);
  }

  Future<Result<IActionIoSessionControl>> start(
    String executionId,
    Future<Result<IActionIoSessionControl>> Function() create,
  ) {
    if (!accepting || _sessions.containsKey(executionId)) {
      return Future.value(Failure(_failure('ACTION_IO_ADMISSION_CLOSED')));
    }
    final owned = _OwnedSession();
    _sessions[executionId] = owned;
    _publishMetrics();
    return _create(executionId, owned, create);
  }

  Future<Result<IActionIoSessionControl>> _create(
    String id,
    _OwnedSession owned,
    Future<Result<IActionIoSessionControl>> Function() create,
  ) async {
    try {
      final result = await create();
      if (result.isError()) {
        // Failed creation can include uncertain native cleanup. Preserve that
        // uncertainty instead of silently authorizing database shutdown.
        _recordCleanupFailure(result.exceptionOrNull()!);
        _sessions.remove(id);
        _publishMetrics();
        owned.done.complete();
        return result;
      }
      final session = result.getOrThrow();
      owned.session = session;
      unawaited(
        _observe(
          id,
          owned,
          _accepting && !owned.cancelRequested ? session.runAndDrain() : _stopOwned(owned, session),
        ),
      );
      return result;
    } on Object {
      final failure = _failure('ACTION_IO_CLEANUP_FAILED');
      _recordCleanupFailure(failure);
      _sessions.remove(id);
      _publishMetrics();
      if (!owned.done.isCompleted) owned.done.complete();
      return Failure(failure);
    }
  }

  Future<void> _observe(String id, _OwnedSession owned, Future<Result<Unit>> completion) async {
    try {
      final result = await completion;
      if (result.isError()) _recordCleanupFailure(result.exceptionOrNull()!);
    } on Object {
      _recordCleanupFailure(_failure('ACTION_IO_CLEANUP_FAILED'));
    } finally {
      // A normal run can finish while cancellation is still releasing native
      // resources. Keep ownership until that independently observed work ends.
      // _stop records any failure before completing this future.
      final stopping = owned.stopping;
      if (stopping != null) await stopping;
      _sessions.remove(id);
      _publishMetrics();
      if (!owned.done.isCompleted) owned.done.complete();
    }
  }

  Future<Result<Unit>> shutdown() {
    _accepting = false;
    return _shutdown ??= _drain();
  }

  Future<Result<Unit>> _drain() async {
    final launches = _launches.values.toList();
    for (final launch in launches) {
      try {
        final result = await launch.cancelPending();
        if (result.isError()) _recordCleanupFailure(result.exceptionOrNull()!);
      } on Object {
        _recordCleanupFailure(_failure('ACTION_IO_LAUNCH_COMPLETION_UNKNOWN'));
      }
    }
    final owned = _sessions.values.toList();
    // Await creation-in-progress through each ownership record. Once its factory
    // resolves, _create observes closed admission and stops the suspended task.
    final stopping = <Future<Result<Unit>>>[
      for (final entry in owned)
        if (entry.session != null) _stopOwned(entry, entry.session!),
    ];
    await Future.wait(stopping);
    await Future.wait(owned.map((entry) => entry.done.future));
    await Future.wait(launches.map((entry) => entry.done.future));
    if (_cleanupFailures.isNotEmpty) return Failure(_failure('ACTION_IO_CLEANUP_FAILED'));
    return const Success(unit);
  }

  Future<Result<Unit>> _stop(IActionIoSessionControl session) async {
    try {
      final result = await session.stopAndDrain();
      if (result.isError()) _recordCleanupFailure(result.exceptionOrNull()!);
      return result;
    } on Object {
      final failure = _failure('ACTION_IO_CLEANUP_FAILED');
      _recordCleanupFailure(failure);
      return Failure(failure);
    }
  }

  void _recordCleanupFailure(Exception failure) {
    _cleanupFailures.add(failure);
    _publishMetrics();
  }

  void _publishMetrics() => _metrics?.setLifecycle(
    launches: _launches.length,
    sessions: _sessions.length,
    cleanupUnconfirmed: _cleanupFailures.isNotEmpty,
  );

  ActionRuntimeFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'I/O session admission or native cleanup could not be confirmed.',
    code: code,
    context: {'retryable': false},
  );
}

final class _OwnedLaunch {
  _OwnedLaunch(this.cancelPending);
  final Future<Result<Unit>> Function() cancelPending;
  final Completer<void> done = Completer<void>();
}

final class _OwnedSession {
  final Completer<void> done = Completer<void>();
  IActionIoSessionControl? session;
  bool cancelRequested = false;
  Future<Result<Unit>>? stopping;
}
