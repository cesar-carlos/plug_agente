import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Bounded, deduplicated cleanup queue for native streaming connections.
///
/// `odbc_fast` does not expose a force-close API. A timed-out caller therefore
/// observes a failure while the native cleanup remains owned by this tracker
/// until it completes. Keeping the queue bounded prevents a disconnect storm
/// from consuming every native worker.
final class OdbcStreamingDisconnectTracker {
  OdbcStreamingDisconnectTracker({
    this.maxInFlight = defaultMaxInFlight,
    this.maxPending = defaultMaxPending,
    this.observedTimeout = defaultObservedTimeout,
  }) : assert(maxInFlight > 0, 'maxInFlight must be positive'),
       assert(maxPending > 0 && maxPending <= maximumPending, 'maxPending must be within bounds');

  static const int defaultMaxInFlight = 16;
  static const int defaultMaxPending = 64;
  static const int maximumPending = 256;
  static const Duration defaultObservedTimeout = Duration(seconds: 8);

  final int maxInFlight;
  final int maxPending;
  final Duration observedTimeout;
  final Queue<_QueuedDisconnect> _pending = Queue<_QueuedDisconnect>();
  final Map<String, Future<Result<void>>> _tracked = <String, Future<Result<void>>>{};
  int _running = 0;

  /// Includes both running work and accepted work waiting for a slot.
  int get inFlightCount => _tracked.length;
  int get runningCount => _running;
  int get pendingCount => _pending.length;
  bool get isSaturated => _pending.length >= maxPending;

  Future<Result<void>> run({
    required String connectionId,
    required Future<Result<void>> Function(String connectionId) disconnect,
    Duration? timeout,
    void Function()? onTimeout,
    void Function()? onFailure,
    void Function()? onSaturated,
    void Function()? onComplete,
  }) async {
    if (connectionId.isEmpty) {
      return const Success(unit);
    }

    final existing = _tracked[connectionId];
    if (existing != null) {
      return _observe(existing, timeout: timeout, onTimeout: onTimeout, onFailure: onFailure);
    }
    if (_pending.length >= maxPending) {
      onSaturated?.call();
      developer.log(
        'Streaming disconnect queue is saturated; new cleanup was not started',
        name: 'odbc_streaming_disconnect_tracker',
        level: 900,
        error: <String, Object?>{
          'running': _running,
          'pending': _pending.length,
          'max_in_flight': maxInFlight,
          'max_pending': maxPending,
        },
      );
      return Failure(
        domain.ConnectionFailure.withContext(
          message: 'Streaming cleanup capacity is temporarily exhausted',
          context: const <String, Object?>{
            'reason': 'stream_disconnect_backlog_saturated',
            'retryable': true,
            'discarded': true,
          },
        ),
      );
    }

    final completer = Completer<Result<void>>();
    final queued = _QueuedDisconnect(
      connectionId: connectionId,
      disconnect: disconnect,
      completer: completer,
      onComplete: onComplete,
    );
    _tracked[connectionId] = completer.future;
    _pending.add(queued);
    _pump();
    return _observe(completer.future, timeout: timeout, onTimeout: onTimeout, onFailure: onFailure);
  }

  Future<Result<void>> _observe(
    Future<Result<void>> work, {
    Duration? timeout,
    void Function()? onTimeout,
    void Function()? onFailure,
  }) async {
    try {
      final result = await work.timeout(timeout ?? observedTimeout);
      if (result.isSuccess()) {
        return const Success(unit);
      }
      onFailure?.call();
      return Failure(result.exceptionOrNull()!);
    } on TimeoutException catch (error) {
      onTimeout?.call();
      return Failure(
        domain.ConnectionFailure.withContext(
          message: 'Streaming disconnect did not finish within the expected time',
          cause: error,
          context: <String, Object?>{
            'reason': OdbcContextConstants.streamCancelDisconnectTimeoutReason,
            'discarded': true,
            'in_flight': true,
            'timeout_ms': (timeout ?? observedTimeout).inMilliseconds,
          },
        ),
      );
    }
  }

  void _pump() {
    while (_running < maxInFlight && _pending.isNotEmpty) {
      final queued = _pending.removeFirst();
      _running++;
      unawaited(_runQueued(queued));
    }
  }

  Future<void> _runQueued(_QueuedDisconnect queued) async {
    Result<void> result;
    try {
      final disconnectResult = await queued.disconnect(queued.connectionId);
      result = disconnectResult.fold(
        (_) => const Success(unit),
        (error) => OdbcErrorInspector.isInvalidConnectionId(error)
            ? const Success(unit)
            : Failure(
                OdbcFailureMapper.mapConnectionError(
                  error,
                  operation: 'streaming_disconnect',
                  context: const <String, Object?>{
                    'reason': OdbcContextConstants.streamCancelDisconnectFailedReason,
                    'discarded': true,
                  },
                ),
              ),
      );
    } on Object catch (error) {
      result = Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'streaming_disconnect',
          context: const <String, Object?>{
            'reason': OdbcContextConstants.streamCancelDisconnectFailedReason,
            'discarded': true,
          },
        ),
      );
    }

    if (!queued.completer.isCompleted) {
      queued.completer.complete(result);
    }
    queued.onComplete?.call();
    _running--;
    if (identical(_tracked[queued.connectionId], queued.completer.future)) {
      _tracked.remove(queued.connectionId);
    }
    _pump();
  }

  /// Waits for accepted cleanup without abandoning native handles.
  Future<void> drain({Duration? timeout}) async {
    if (_tracked.isEmpty) {
      return;
    }
    final pending = List<Future<Result<void>>>.of(_tracked.values);
    try {
      final wait = Future.wait(pending);
      if (timeout == null) {
        await wait;
      } else {
        await wait.timeout(timeout);
      }
    } on TimeoutException {
      developer.log(
        'Streaming disconnect drain timed out; native cleanup remains tracked',
        name: 'odbc_streaming_disconnect_tracker',
        level: 900,
        error: <String, Object?>{
          'running': _running,
          'pending': _pending.length,
          'reason': OdbcContextConstants.streamDisconnectStillInFlightReason,
        },
      );
    }
  }
}

final class _QueuedDisconnect {
  const _QueuedDisconnect({
    required this.connectionId,
    required this.disconnect,
    required this.completer,
    this.onComplete,
  });

  final String connectionId;
  final Future<Result<void>> Function(String connectionId) disconnect;
  final Completer<Result<void>> completer;
  final void Function()? onComplete;
}
