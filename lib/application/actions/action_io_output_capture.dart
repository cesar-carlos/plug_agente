import 'dart:async';

import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:result_dart/result_dart.dart';

/// Persists each native block before requesting further data from that stream.
final class ActionIoOutputCapture {
  ActionIoOutputCapture({
    required this.executionId,
    required IActionIoOutputJournal journal,
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required Future<Result<Unit>> Function() terminate,
  }) : _journal = journal,
       _terminate = terminate {
    done = _captureBoth(stdout, stderr);
  }

  final String executionId;
  final IActionIoOutputJournal _journal;
  final Future<Result<Unit>> Function() _terminate;
  late final Future<Result<Unit>> done;
  Future<void>? _termination;
  Future<Result<Unit>>? _finalizing;
  Future<Result<Unit>>? _draining;
  ActionFailure? _primaryFailure;
  final List<ActionFailure> _secondaryFailures = [];

  List<ActionFailure> get secondaryFailures => List.unmodifiable(_secondaryFailures);
  ActionFailure? get primaryFailure => _primaryFailure;

  /// Call only after observing the process exit. A drain timeout closes the
  /// durable capture but does not mean native workers have released their handles.
  Future<Result<Unit>> finishAfterExit(int exitCode, {ActionFailure? executionFailure}) =>
      _finalizing ??= _finishAfterExit(exitCode, executionFailure);

  /// Separates draining from durable finalization so the owner can confirm
  /// process-tree cleanup before committing a terminal result.
  Future<Result<Unit>> drainAfterExit() => _draining ??= _drainAfterExit();

  Future<Result<Unit>> _drainAfterExit() async {
    try {
      await done.timeout(ActionIoLimits.drainTimeout);
    } on TimeoutException {
      // _fail records the primary cause synchronously before waiting for native
      // termination. Keep that future alive; never confuse timeout with cleanup.
      unawaited(
        _fail(
          ActionRuntimeFailure.withContext(
            message: 'Output capture did not finish within the allowed drain time.',
            code: 'ACTION_IO_DRAIN_TIMEOUT',
            context: {'retryable': false},
          ),
        ),
      );
    }
    final failure = _primaryFailure;
    return failure == null ? const Success(unit) : Failure(failure);
  }

  Future<Result<Unit>> _finishAfterExit(int exitCode, ActionFailure? executionFailure) async {
    await drainAfterExit();
    final failure = executionFailure ?? _primaryFailure;
    if (executionFailure != null && _primaryFailure != null && !identical(executionFailure, _primaryFailure)) {
      _secondaryFailures.add(_primaryFailure!);
    }
    final recorded = await _journal.finish(
      executionId,
      exitCode: exitCode,
      complete: _primaryFailure == null,
      failureCode: failure?.code,
    );
    if (recorded.isError()) {
      final storageFailure = _mapFailure(recorded.exceptionOrNull()!, 'ACTION_IO_STORAGE_FAILED');
      if (failure == null) return Failure(storageFailure);
      _secondaryFailures.add(storageFailure);
    }
    return failure == null ? const Success(unit) : Failure(failure);
  }

  /// Shutdown must await actual stream and termination completion before closing
  /// the journal or releasing native handles, including after a drain timeout.
  Future<void> waitForCleanup() async {
    await done;
    await _termination;
  }

  Future<Result<Unit>> _captureBoth(Stream<List<int>> stdout, Stream<List<int>> stderr) async {
    await Future.wait([
      _capture(stdout, ActionIoStream.stdout),
      _capture(stderr, ActionIoStream.stderr),
    ]);
    final failure = _primaryFailure;
    return failure == null ? const Success(unit) : Failure(failure);
  }

  Future<void> _capture(Stream<List<int>> source, ActionIoStream stream) async {
    try {
      await for (final block in source) {
        if (_primaryFailure != null) break;
        // Empty stream notifications carry no output and do not imply EOF.
        if (block.isEmpty) continue;
        final result = await _journal.append(executionId, stream, block);
        if (result.isError()) {
          await _fail(result.exceptionOrNull()!);
          break;
        }
      }
    } on Object catch (error) {
      await _fail(error);
    }
  }

  Future<void> _fail(Object error) async {
    final failure = _mapFailure(error, 'ACTION_IO_CAPTURE_FAILED');
    if (_primaryFailure == null) {
      _primaryFailure = failure;
    } else if (!identical(_primaryFailure, failure)) {
      _secondaryFailures.add(failure);
    }
    await (_termination ??= _stop());
  }

  Future<void> _stop() async {
    try {
      final result = await _terminate();
      if (result.isError()) {
        _secondaryFailures.add(_mapFailure(result.exceptionOrNull()!, 'ACTION_IO_CLEANUP_FAILED'));
      }
    } on Object catch (error) {
      _secondaryFailures.add(_mapFailure(error, 'ACTION_IO_CLEANUP_FAILED'));
    }
  }

  ActionFailure _mapFailure(Object error, String code) => error is ActionFailure
      ? error
      : ActionRuntimeFailure.withContext(
          message: 'The action output could not be captured completely.',
          code: code,
          context: {'retryable': false, 'cause_type': error.runtimeType.toString()},
        );
}
