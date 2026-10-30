import 'dart:async';

import 'package:plug_agente/application/actions/action_io_input_delivery.dart';
import 'package:plug_agente/application/actions/action_io_output_capture.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_control.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoSessionOutcome {
  const ActionIoSessionOutcome({required this.exitCode, required this.outputComplete});
  final int exitCode;
  final bool outputComplete;
}

/// Owns an already admitted, protected and suspended process. Its caller must
/// commit starting state and reauthorize before creating that process.
final class ActionIoRunningSession implements IActionIoSessionControl {
  ActionIoRunningSession({
    required this.executionId,
    required IActionIoProcess process,
    required IActionIoJournal inputJournal,
    required IActionIoOutputJournal outputJournal,
    required Future<Result<Unit>> Function() authorize,
    required this.deadline,
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    DateTime Function()? now,
  }) : _process = process,
       _inputJournal = inputJournal,
       _outputJournal = outputJournal,
       _authorize = authorize,
       _acceptedExitCodes = Set<int>.unmodifiable(exitCodePolicy.acceptedExitCodes),
       _now = now ?? DateTime.now;

  final String executionId;
  final DateTime deadline;
  final Set<int> _acceptedExitCodes;
  final IActionIoProcess _process;
  final IActionIoJournal _inputJournal;
  final IActionIoOutputJournal _outputJournal;
  final Future<Result<Unit>> Function() _authorize;
  final DateTime Function() _now;
  Future<Result<ActionIoSessionOutcome>>? _running;
  Future<Result<Unit>>? _termination;
  ActionFailure? _primaryFailure;
  final List<ActionFailure> _secondaryFailures = [];
  bool _stopInput = false;
  bool _settled = false;
  bool _cleanupConfirmed = false;

  List<ActionFailure> get secondaryFailures => List.unmodifiable(_secondaryFailures);
  Future<Result<ActionIoSessionOutcome>> run() => _running ??= _run();

  @override
  Future<Result<Unit>> runAndDrain() async {
    await run();
    return _cleanupConfirmed ? const Success(unit) : Failure(_failure('ACTION_IO_CLEANUP_FAILED'));
  }

  @override
  Future<Result<Unit>> stopAndDrain() async {
    await cancel();
    return runAndDrain();
  }

  Future<Result<Unit>> cancel() {
    if (_settled) return Future.value(const Success(unit));
    _record(_failure('ACTION_CANCELLED'));
    _stopInput = true;
    return _stop();
  }

  Future<Result<ActionIoSessionOutcome>> _run() async {
    late final ActionIoOutputCapture capture;
    capture = ActionIoOutputCapture(
      executionId: executionId,
      journal: _outputJournal,
      stdout: _process.stdout,
      stderr: _process.stderr,
      terminate: () {
        final failure = capture.primaryFailure;
        if (failure != null) _record(failure);
        return _stop();
      },
    );
    final delivery = ActionIoInputDelivery(
      executionId: executionId,
      journal: _inputJournal,
      pipe: _process.input,
      authorize: _authorize,
      terminate: _stop,
      now: _now,
    );
    Future<void>? delivering;
    Result<int> exited;
    try {
      if (_primaryFailure != null) throw _primaryFailure!;
      (await _authorize()).getOrThrow();
      (await _inputJournal.markRunning(executionId)).getOrThrow();
      (await _authorize()).getOrThrow();
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) throw _failure('ACTION_TIMEOUT');
      if (_primaryFailure != null) throw _primaryFailure!;
      _process.resume().getOrThrow();
      delivering = _deliver(delivery);
      exited = await _process.exitCode.timeout(remaining);
    } on Object catch (error) {
      _record(error is TimeoutException ? _failure('ACTION_TIMEOUT') : error);
      await _stop();
      // Timeout is not native completion. Retain ownership until exit is observed.
      exited = await _process.exitCode;
    }
    _stopInput = true;
    if (exited.isError()) {
      _record(exited.exceptionOrNull()!);
      await _stop();
    }
    if (exited.isSuccess() && !_acceptedExitCodes.contains(exited.getOrThrow())) {
      _record(
        ActionRuntimeFailure.withContext(
          message: 'The process returned an exit code rejected by the saved action policy.',
          code: AgentActionFailureCode.exitCodeRejected,
          context: {'exit_code': exited.getOrThrow(), 'retryable': false},
        ),
      );
    }
    await delivering;
    await delivery.waitForNativeCompletion();
    for (final failure in delivery.secondaryFailures) {
      _secondaryFailures.add(_mapped(failure));
    }
    final drained = await capture.drainAfterExit();
    if (drained.isError()) _record(drained.exceptionOrNull()!);
    Result<Unit> closed;
    try {
      closed = await _process.close();
    } on Object catch (error) {
      closed = Failure(_mapped(error));
    }
    if (closed.isError()) _record(closed.exceptionOrNull()!);
    await capture.waitForCleanup();
    _secondaryFailures.addAll(capture.secondaryFailures);
    final confirmed = exited.isSuccess() && closed.isSuccess();
    _cleanupConfirmed = confirmed;
    final complete = confirmed && drained.isSuccess();
    final recorded = await _outputJournal.finish(
      executionId,
      exitCode: exited.getOrNull(),
      complete: complete,
      processTerminated: confirmed,
      failureCode: _primaryFailure?.code,
    );
    if (recorded.isError()) _record(recorded.exceptionOrNull()!);
    _settled = true;
    final failure = _primaryFailure;
    if (failure != null) return Failure(failure);
    return Success(ActionIoSessionOutcome(exitCode: exited.getOrThrow(), outputComplete: complete));
  }

  Future<void> _deliver(ActionIoInputDelivery delivery) async {
    try {
      while (!_stopInput) {
        final result = await delivery.deliverNext(deadline: deadline);
        if (result.isError()) {
          _record(result.exceptionOrNull()!);
          await _stop();
          return;
        }
        final receipt = result.getOrThrow().receipt;
        if (receipt?.stdinState == ActionIoStdinState.closed) return;
        if (receipt == null) await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } on Object catch (error) {
      _record(error);
      await _stop();
    }
  }

  Future<Result<Unit>> _stop() => _termination ??= _terminate();

  Future<Result<Unit>> _terminate() async {
    try {
      final result = await _process.terminate();
      if (result.isError()) _secondaryFailures.add(_mapped(result.exceptionOrNull()!));
      return result;
    } on Object catch (error) {
      final failure = _mapped(error);
      _secondaryFailures.add(failure);
      return Failure(failure);
    }
  }

  void _record(Object error) {
    final failure = _mapped(error);
    if (_primaryFailure == null) {
      _primaryFailure = failure;
    } else if (!identical(_primaryFailure, failure)) {
      _secondaryFailures.add(failure);
    }
  }

  ActionFailure _mapped(Object error) => error is ActionFailure ? error : _failure('ACTION_OUTCOME_UNKNOWN');
  ActionFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'The faithful action session could not complete successfully.',
    code: code,
    context: const {'retryable': false},
  );
}
