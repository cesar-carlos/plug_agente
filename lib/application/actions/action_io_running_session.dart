import 'dart:async';

import 'package:plug_agente/application/actions/action_io_input_delivery.dart';
import 'package:plug_agente/application/actions/action_io_output_capture.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal_changes.dart';
import 'package:plug_agente/domain/actions/action_io_lifecycle.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_lifecycle_journal.dart';
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
  final Stopwatch _elapsed = Stopwatch();

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
    _elapsed.start();
    _log('session_started');
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
      await _milestone(ActionIoMilestone.processCreated, pid: _process.pid);
      if (_primaryFailure != null) throw _primaryFailure!;
      (await _authorize()).getOrThrow();
      (await _inputJournal.markRunning(executionId)).getOrThrow();
      (await _authorize()).getOrThrow();
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) throw _failure('ACTION_TIMEOUT');
      if (_primaryFailure != null) throw _primaryFailure!;
      _process.resume().getOrThrow();
      await _milestone(ActionIoMilestone.processResumed);
      delivering = _deliver(delivery);
      final waitRemaining = deadline.difference(_now());
      if (waitRemaining <= Duration.zero) throw _failure('ACTION_TIMEOUT');
      _log('waiting_for_process_exit');
      exited = await _process.exitCode.timeout(waitRemaining);
    } on Object catch (error) {
      if (error is TimeoutException || (error is ActionFailure && error.code == 'ACTION_TIMEOUT')) {
        await _milestone(ActionIoMilestone.timeoutRequested);
      }
      _record(error is TimeoutException ? _failure('ACTION_TIMEOUT') : error);
      await _stop();
      // Timeout is not native completion. Retain ownership until exit is observed.
      _log('waiting_for_exit_after_termination');
      exited = await _process.exitCode;
    }
    if (exited.isSuccess()) await _milestone(ActionIoMilestone.processExited);
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
    _log('waiting_for_input_completion');
    await delivering;
    await delivery.waitForNativeCompletion();
    for (final failure in delivery.secondaryFailures) {
      _secondaryFailures.add(_mapped(failure));
    }
    _log('capture_drain_started');
    final drained = await capture.drainAfterExit();
    if (drained.isSuccess()) await _milestone(ActionIoMilestone.captureDrained);
    if (drained.isError()) _record(drained.exceptionOrNull()!);
    Result<Unit> closed;
    _log('process_cleanup_started');
    try {
      closed = await _process.close();
    } on Object catch (error) {
      closed = Failure(_mapped(error));
    }
    if (closed.isError()) _record(closed.exceptionOrNull()!);
    await capture.waitForCleanup();
    _secondaryFailures.addAll(capture.secondaryFailures);
    final confirmed = exited.isSuccess() && closed.isSuccess();
    if (confirmed) await _milestone(ActionIoMilestone.cleanupConfirmed);
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
    _log('session_finished', code: _primaryFailure?.code);
    _elapsed.stop();
    final failure = _primaryFailure;
    if (failure != null) return Failure(failure);
    return Success(ActionIoSessionOutcome(exitCode: exited.getOrThrow(), outputComplete: complete));
  }

  Future<void> _deliver(ActionIoInputDelivery delivery) async {
    final journal = _inputJournal;
    final changes = journal is IActionIoJournalChanges
        ? (journal as IActionIoJournalChanges).observeChanges(executionId)
        : null;
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
        if (receipt == null) {
          const fallback = Duration(milliseconds: 100);
          await (changes?.wait(fallback) ?? Future<void>.delayed(fallback));
        }
      }
    } on Object catch (error) {
      _record(error);
      await _stop();
    } finally {
      changes?.close();
    }
  }

  Future<Result<Unit>> _stop() => _termination ??= _terminate();

  Future<Result<Unit>> _terminate() async {
    _log('process_tree_termination_started');
    try {
      final result = await _process.terminate();
      _log(result.isSuccess() ? 'process_tree_termination_returned' : 'process_tree_termination_failed');
      if (result.isError()) _secondaryFailures.add(_mapped(result.exceptionOrNull()!));
      return result;
    } on Object catch (error) {
      _log('process_tree_termination_threw');
      final failure = _mapped(error);
      _secondaryFailures.add(failure);
      return Failure(failure);
    }
  }

  void _record(Object error) {
    final failure = _mapped(error);
    _log('session_failure', code: failure.code);
    if (_primaryFailure == null) {
      _primaryFailure = failure;
    } else if (!identical(_primaryFailure, failure)) {
      _secondaryFailures.add(failure);
    }
  }

  Future<void> _milestone(ActionIoMilestone milestone, {int? pid}) async {
    _log(milestone.name, pid: pid);
    final journal = _inputJournal;
    if (journal is! IActionIoLifecycleJournal) return;
    try {
      final result = await (journal as IActionIoLifecycleJournal).recordMilestone(executionId, milestone, pid: pid);
      if (result.isError()) _record(result.exceptionOrNull()!);
    } on Object catch (error) {
      _record(error);
    }
  }

  void _log(String stage, {String? code, int? pid}) => AppLogger.operational(
    'Action IO lifecycle',
    context: {
      'execution_id': executionId,
      'stage': stage,
      'at_utc': _now().toUtc().toIso8601String(),
      'elapsed_ms': _elapsed.elapsedMilliseconds,
      'pid': ?pid,
      'failure_code': ?code,
    },
  );

  ActionFailure _mapped(Object error) => error is ActionFailure ? error : _failure('ACTION_OUTCOME_UNKNOWN');
  ActionFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'The faithful action session could not complete successfully.',
    code: code,
    context: const {'retryable': false},
  );
}
