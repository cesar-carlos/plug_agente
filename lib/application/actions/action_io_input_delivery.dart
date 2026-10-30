import 'dart:async';

import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoDeliveryAttempt {
  const ActionIoDeliveryAttempt(this.receipt);
  final ActionIoMessageReceipt? receipt;
}

/// One serialized delivery worker per execution; never retries uncertain writes.
final class ActionIoInputDelivery {
  ActionIoInputDelivery({
    required this.executionId,
    required IActionIoJournal journal,
    required IActionIoInputPipe pipe,
    required Future<Result<Unit>> Function() authorize,
    required Future<Result<Unit>> Function() terminate,
    DateTime Function()? now,
  }) : _journal = journal,
       _pipe = pipe,
       _authorize = authorize,
       _terminate = terminate,
       _now = now ?? DateTime.now;

  final String executionId;
  final IActionIoJournal _journal;
  final IActionIoInputPipe _pipe;
  final Future<Result<Unit>> Function() _authorize;
  final Future<Result<Unit>> Function() _terminate;
  final DateTime Function() _now;
  bool _busy = false;
  bool _stopped = false;
  Future<Result<Unit>>? _native;
  final List<Exception> _secondaryFailures = [];

  List<Exception> get secondaryFailures => List.unmodifiable(_secondaryFailures);

  /// Shutdown must await this before releasing resources owned by a native call.
  Future<void> waitForNativeCompletion() async {
    await _native;
  }

  Future<Result<ActionIoDeliveryAttempt>> deliverNext({required DateTime deadline}) async {
    if (_busy || _stopped) return Failure(_failure('ACTION_IO_DELIVERY_UNAVAILABLE'));
    _busy = true;
    ActionIoPendingInput? input;
    var nativeStarted = false;
    try {
      final permission = await _authorize();
      if (permission.isError()) return Failure(permission.exceptionOrNull()!);
      final poll = await _journal.beginNextInput(executionId);
      if (poll.isError()) return Failure(poll.exceptionOrNull()!);
      input = poll.getOrThrow().input;
      if (input == null) return const Success(ActionIoDeliveryAttempt(null));
      // The durable writing claim may have waited for disk; resolve policy again.
      final currentPermission = await _authorize();
      if (currentPermission.isError()) {
        return await _fail(input, currentPermission.exceptionOrNull()!, started: false);
      }
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) return await _fail(input, _failure('ACTION_TIMEOUT'), started: false);
      final timeout = remaining < ActionIoLimits.writeTimeout ? remaining : ActionIoLimits.writeTimeout;
      nativeStarted = true;
      // Do not clear this future on timeout: the native worker still owns its pipe.
      final operation = _invoke(input);
      _native = operation;
      unawaited(
        operation.then((_) {
          if (identical(_native, operation)) _native = null;
        }),
      );
      final written = await operation.timeout(timeout);
      if (written.isError()) return await _fail(input, written.exceptionOrNull()!, started: true);
      final receipt = await _journal.finishInput(
        executionId,
        input.receipt.messageId,
        ActionIoDeliveryState.written,
        confirmedBytes: input.bytes.length,
      );
      if (receipt.isError()) {
        // Bytes may already be written; preserve the writing record for recovery.
        _stopped = true;
        await _stop();
        return Failure(receipt.exceptionOrNull()!);
      }
      if (input.close) _stopped = true;
      return Success(ActionIoDeliveryAttempt(receipt.getOrThrow()));
    } on Object catch (error) {
      final failure = error is Exception ? error : _failure('ACTION_OUTCOME_UNKNOWN');
      if (input != null) return _fail(input, failure, started: nativeStarted);
      return Failure(_failure('ACTION_IO_DELIVERY_UNAVAILABLE'));
    } finally {
      _busy = false;
    }
  }

  Future<Result<Unit>> _invoke(ActionIoPendingInput input) async {
    try {
      return await (input.close ? _pipe.close() : _pipe.write(input.bytes));
    } on Object {
      return Failure(ActionIoPipeFailure());
    }
  }

  Future<Result<ActionIoDeliveryAttempt>> _fail(
    ActionIoPendingInput input,
    Exception cause, {
    required bool started,
  }) async {
    _stopped = true;
    final failure = started
        ? (cause is ActionIoPipeFailure ? cause : ActionIoPipeFailure())
        : (cause is ActionFailure ? cause : _failure('ACTION_IO_DELIVERY_UNAVAILABLE'));
    final recorded = await _journal.finishInput(
      executionId,
      input.receipt.messageId,
      started ? ActionIoDeliveryState.unknown : ActionIoDeliveryState.failed,
      confirmedBytes: started ? (failure is ActionIoPipeFailure ? failure.confirmedBytes : null) : 0,
      failureCode: failure.code,
    );
    if (recorded.isError()) _secondaryFailures.add(recorded.exceptionOrNull()!);
    await _stop();
    return Failure(failure);
  }

  Future<void> _stop() async {
    try {
      final result = await _terminate();
      if (result.isError()) _secondaryFailures.add(result.exceptionOrNull()!);
    } on Object {
      _secondaryFailures.add(_failure('ACTION_IO_CLEANUP_FAILED'));
    }
  }

  ActionRuntimeFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'Input delivery cannot continue for this execution.',
    code: code,
    context: {'retryable': false},
  );
}
