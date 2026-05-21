import 'dart:async';

import 'package:plug_agente/application/actions/action_trigger_schedule_calculator.dart';
import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:result_dart/result_dart.dart';

abstract class AgentActionSchedulerTimer {
  void cancel();
}

typedef AgentActionSchedulerTimerFactory =
    AgentActionSchedulerTimer Function(
      Duration delay,
      void Function() callback,
    );

class AgentActionSchedulerIssue {
  const AgentActionSchedulerIssue({
    required this.triggerId,
    required this.message,
    this.code,
  });

  final String triggerId;
  final String message;
  final String? code;
}

class AgentActionSchedulerSnapshot {
  const AgentActionSchedulerSnapshot({
    required this.scheduledCount,
    required this.skippedCount,
    this.issues = const [],
  });

  final int scheduledCount;
  final int skippedCount;
  final List<AgentActionSchedulerIssue> issues;

  bool get hasIssues => issues.isNotEmpty;
}

class AgentActionTriggerScheduler {
  AgentActionTriggerScheduler(
    this._repository,
    this._dispatchTrigger, {
    AgentActionTriggerScheduleCalculator calculator = const AgentActionTriggerScheduleCalculator(),
    AgentActionSchedulerTimerFactory? timerFactory,
    FeatureFlags? featureFlags,
    IAgentActionSchedulerInstanceLock? schedulerInstanceLock,
    DateTime Function()? now,
  }) : _calculator = calculator,
       _timerFactory = timerFactory ?? _defaultTimerFactory,
       _featureFlags = featureFlags,
       _schedulerInstanceLock = schedulerInstanceLock,
       _now = now ?? DateTime.now;

  final IAgentActionRepository _repository;
  final DispatchAgentActionTrigger _dispatchTrigger;
  final AgentActionTriggerScheduleCalculator _calculator;
  final AgentActionSchedulerTimerFactory _timerFactory;
  final FeatureFlags? _featureFlags;
  final IAgentActionSchedulerInstanceLock? _schedulerInstanceLock;
  final DateTime Function() _now;
  final Map<String, AgentActionSchedulerTimer> _timersByTriggerId = <String, AgentActionSchedulerTimer>{};

  bool _started = false;
  bool _bootstrapDisabled = false;
  String? _lastStartIssueReason;

  int get scheduledTimerCount => _timersByTriggerId.length;

  bool get isBootstrapDisabled => _bootstrapDisabled;

  bool get isTemporalSchedulerStarted => _started;

  /// Stable `AgentActionTriggerConstants.*Reason` when [start] did not arm temporal timers.
  String? get lastStartIssueReason => _lastStartIssueReason;

  Future<Result<AgentActionSchedulerSnapshot>> start() async {
    final featureGateResult = _ensureSchedulerFeatureGateAllows();
    if (featureGateResult.isError()) {
      _lastStartIssueReason = _reasonFromFailure(featureGateResult.exceptionOrNull()!);
      return Failure(featureGateResult.exceptionOrNull()!);
    }

    final operationalResult = _ensureSchedulerOperational();
    if (operationalResult.isError()) {
      _lastStartIssueReason = AgentActionTriggerConstants.schedulerBootstrapFailedReason;
      return Failure(operationalResult.exceptionOrNull()!);
    }

    if (_started) {
      return Success(
        AgentActionSchedulerSnapshot(
          scheduledCount: _timersByTriggerId.length,
          skippedCount: 0,
        ),
      );
    }

    final lock = _schedulerInstanceLock;
    if (lock != null) {
      final lockResult = await lock.tryAcquire();
      if (lockResult.isError()) {
        _lastStartIssueReason = _reasonFromFailure(lockResult.exceptionOrNull()!);
        return Failure(lockResult.exceptionOrNull()!);
      }
    }

    _started = true;
    final reloadResult = await reloadTemporalTriggers();
    if (reloadResult.isError()) {
      await _disableAfterBootstrapFailure();
      return reloadResult;
    }

    _lastStartIssueReason = null;
    return reloadResult;
  }

  Future<Result<AgentActionSchedulerSnapshot>> reloadTemporalTriggers() async {
    final featureGateResult = _ensureSchedulerFeatureGateAllows();
    if (featureGateResult.isError()) {
      _cancelAllTimers();
      return Failure(featureGateResult.exceptionOrNull()!);
    }

    final operationalResult = _ensureSchedulerOperational();
    if (operationalResult.isError()) {
      _cancelAllTimers();
      return Failure(operationalResult.exceptionOrNull()!);
    }

    _cancelAllTimers();

    final triggersResult = await _repository.listTriggers(
      isEnabled: true,
      types: const {
        AgentActionTriggerType.once,
        AgentActionTriggerType.interval,
        AgentActionTriggerType.daily,
        AgentActionTriggerType.weekly,
        AgentActionTriggerType.monthly,
      },
    );
    if (triggersResult.isError()) {
      await _disableAfterBootstrapFailure();
      return Failure(triggersResult.exceptionOrNull()!);
    }

    final issues = <AgentActionSchedulerIssue>[];
    var skippedCount = 0;
    for (final trigger in triggersResult.getOrThrow()) {
      final scheduled = await _scheduleTemporalTrigger(trigger);
      scheduled.fold(
        (didSchedule) {
          if (!didSchedule) {
            skippedCount += 1;
          }
        },
        (failure) {
          skippedCount += 1;
          issues.add(_issueFor(trigger.id, failure));
        },
      );
    }

    return Success(
      AgentActionSchedulerSnapshot(
        scheduledCount: _timersByTriggerId.length,
        skippedCount: skippedCount,
        issues: issues,
      ),
    );
  }

  Future<Result<int>> dispatchAppStartTriggers() {
    final featureGateResult = _ensureLifecycleFeatureGateAllows();
    if (featureGateResult.isError()) {
      return Future<Result<int>>.value(Failure(featureGateResult.exceptionOrNull()!));
    }

    final operationalResult = _ensureSchedulerOperational();
    if (operationalResult.isError()) {
      return Future<Result<int>>.value(Failure(operationalResult.exceptionOrNull()!));
    }

    return _dispatchLifecycleTriggers(AgentActionTriggerType.appStart);
  }

  Future<Result<int>> dispatchAppCloseTriggers({
    Duration timeoutPerTrigger = const Duration(seconds: 5),
  }) {
    final featureGateResult = _ensureLifecycleFeatureGateAllows();
    if (featureGateResult.isError()) {
      return Future<Result<int>>.value(Failure(featureGateResult.exceptionOrNull()!));
    }

    final operationalResult = _ensureSchedulerOperational();
    if (operationalResult.isError()) {
      return Future<Result<int>>.value(Failure(operationalResult.exceptionOrNull()!));
    }

    return _dispatchLifecycleTriggers(
      AgentActionTriggerType.appClose,
      timeoutPerTrigger: timeoutPerTrigger,
    );
  }

  void stop() {
    _started = false;
    _cancelAllTimers();
    unawaited(_schedulerInstanceLock?.release());
  }

  Future<void> _disableAfterBootstrapFailure() async {
    _bootstrapDisabled = true;
    _started = false;
    _lastStartIssueReason = AgentActionTriggerConstants.schedulerBootstrapFailedReason;
    _cancelAllTimers();
    await _schedulerInstanceLock?.release();
  }

  static String? _reasonFromFailure(Object failure) {
    if (failure is ActionAuthorizationFailure) {
      final reason = failure.context['reason'];
      if (reason is String && reason.trim().isNotEmpty) {
        return reason.trim();
      }
    }

    return AgentActionTriggerConstants.schedulerBootstrapFailedReason;
  }

  Result<void> _ensureSchedulerOperational() {
    if (!_bootstrapDisabled) {
      return const Success(unit);
    }

    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Agent action scheduler is disabled after bootstrap failure.',
        code: AgentActionFailureCode.schedulerBootstrapFailed,
        context: const {
          'reason': AgentActionTriggerConstants.schedulerBootstrapFailedReason,
          'user_message':
              'O agendador de acoes foi desativado apos falha na inicializacao. Reinicie o agente ou revise os gatilhos salvos.',
        },
      ),
    );
  }

  Result<void> _ensureLifecycleFeatureGateAllows() {
    final flags = _featureFlags;
    if (flags == null) {
      return const Success(unit);
    }

    if (!flags.enableAgentActions) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Agent action lifecycle triggers are disabled by feature flag.',
          code: AgentActionFailureCode.featureDisabled,
          context: const {
            'reason': AgentActionGateConstants.featureDisabledReason,
            'user_message': 'Os gatilhos de ciclo de vida das acoes estao desativados neste ambiente.',
          },
        ),
      );
    }

    if (flags.enableAgentActionsMaintenanceMode) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Agent action lifecycle triggers are blocked by maintenance mode.',
          code: AgentActionFailureCode.maintenanceMode,
          context: const {
            'reason': AgentActionGateConstants.maintenanceModeReason,
            'user_message': 'Os gatilhos de ciclo de vida estao bloqueados pelo modo de manutencao.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  Result<void> _ensureSchedulerFeatureGateAllows() {
    final flags = _featureFlags;
    if (flags == null) {
      return const Success(unit);
    }

    if (!flags.enableAgentActions) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Agent action scheduler is disabled by feature flag.',
          code: AgentActionFailureCode.featureDisabled,
          context: const {
            'reason': AgentActionGateConstants.featureDisabledReason,
            'user_message': 'O agendador de acoes esta desativado neste ambiente.',
          },
        ),
      );
    }

    if (flags.enableAgentActionsMaintenanceMode) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Agent action scheduler is blocked by maintenance mode.',
          code: AgentActionFailureCode.maintenanceMode,
          context: const {
            'reason': AgentActionGateConstants.maintenanceModeReason,
            'user_message': 'O agendador de acoes esta bloqueado pelo modo de manutencao.',
          },
        ),
      );
    }

    return const Success(unit);
  }

  Future<Result<bool>> _scheduleTemporalTrigger(
    AgentActionTrigger trigger,
  ) async {
    final decisionResult = _calculator.nextRun(
      trigger: trigger,
      now: _now(),
    );
    if (decisionResult.isError()) {
      return Failure(decisionResult.exceptionOrNull()!);
    }

    final nextRunAt = decisionResult.getOrThrow().nextRunAt;
    if (nextRunAt == null) {
      await _repository.saveTrigger(
        trigger.copyWith(clearNextRunAt: true),
      );
      return const Success(false);
    }

    final updatedTrigger = trigger.copyWith(nextRunAt: nextRunAt);
    final saveResult = await _repository.saveTrigger(updatedTrigger);
    if (saveResult.isError()) {
      return Failure(saveResult.exceptionOrNull()!);
    }

    _timersByTriggerId[trigger.id]?.cancel();
    _timersByTriggerId[trigger.id] = _timerFactory(
      _delayUntil(nextRunAt),
      () => unawaited(_dispatchAndReschedule(trigger.id, nextRunAt)),
    );
    return const Success(true);
  }

  Future<void> _dispatchAndReschedule(
    String triggerId,
    DateTime scheduledAt,
  ) async {
    _timersByTriggerId.remove(triggerId)?.cancel();

    await _dispatchTrigger(
      triggerId: triggerId,
      scheduledAt: scheduledAt,
    );

    final freshTriggerResult = await _repository.getTrigger(triggerId);
    if (freshTriggerResult.isError()) {
      return;
    }

    final freshTrigger = freshTriggerResult.getOrThrow();
    if (!freshTrigger.isEnabled || !freshTrigger.isTemporalTrigger) {
      return;
    }

    final runAt = _now();
    final updatedTrigger = freshTrigger.copyWith(
      lastScheduledAt: scheduledAt,
      lastRunAt: runAt,
      clearNextRunAt: true,
    );
    await _scheduleTemporalTrigger(updatedTrigger);
  }

  Future<Result<int>> _dispatchLifecycleTriggers(
    AgentActionTriggerType type, {
    Duration? timeoutPerTrigger,
  }) async {
    final triggersResult = await _repository.listTriggers(
      isEnabled: true,
      types: {type},
    );
    if (triggersResult.isError()) {
      return Failure(triggersResult.exceptionOrNull()!);
    }

    var dispatchedCount = 0;
    for (final trigger in triggersResult.getOrThrow()) {
      final canDispatchResult = await _canDispatchLifecycleTrigger(
        trigger,
        timeoutPerTrigger: timeoutPerTrigger,
      );
      if (canDispatchResult.isError() || !canDispatchResult.getOrThrow()) {
        continue;
      }

      final dispatchFuture = _dispatchTrigger(triggerId: trigger.id);
      final dispatchResult = timeoutPerTrigger == null
          ? await dispatchFuture
          : await dispatchFuture.timeout(
              timeoutPerTrigger,
              onTimeout: () => Failure(
                ActionTimeoutFailure.withContext(
                  message: 'Action lifecycle trigger dispatch timed out.',
                  code: AgentActionFailureCode.lifecycleTriggerTimeout,
                  context: {
                    'trigger_id': trigger.id,
                    'trigger_type': trigger.type.name,
                    'timeout_ms': timeoutPerTrigger.inMilliseconds,
                    'reason': AgentActionTriggerConstants.lifecycleTriggerTimeoutReason,
                    'user_message': 'O gatilho de fechamento excedeu o tempo limite e foi interrompido.',
                  },
                ),
              ),
            );
      if (dispatchResult.isSuccess()) {
        dispatchedCount += 1;
        await _repository.saveTrigger(
          trigger.copyWith(lastRunAt: _now()),
        );
      }
    }

    return Success(dispatchedCount);
  }

  Future<Result<bool>> _canDispatchLifecycleTrigger(
    AgentActionTrigger trigger, {
    required Duration? timeoutPerTrigger,
  }) async {
    if (trigger.type != AgentActionTriggerType.appClose || timeoutPerTrigger == null) {
      return const Success(true);
    }

    final actionId = trigger.actionId.trim();
    if (actionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger references a blank action id.',
          code: AgentActionFailureCode.triggerActionIdBlank,
          context: {
            'trigger_id': trigger.id,
            'reason': AgentActionTriggerConstants.blankActionIdReason,
            'user_message': 'O gatilho referencia uma acao invalida. Corrija o cadastro do gatilho.',
          },
        ),
      );
    }

    final definitionResult = await _repository.getDefinition(actionId);
    if (definitionResult.isError()) {
      return Failure(definitionResult.exceptionOrNull()!);
    }

    final definition = definitionResult.getOrThrow();
    if (definition.policies.timeout.maxRuntime > timeoutPerTrigger) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action app-close trigger cannot run because maxRuntime exceeds the shutdown budget.',
          code: AgentActionFailureCode.appCloseRuntimeTooLong,
          context: {
            'trigger_id': trigger.id,
            'action_id': actionId,
            'max_runtime_ms': definition.policies.timeout.maxRuntime.inMilliseconds,
            'shutdown_budget_ms': timeoutPerTrigger.inMilliseconds,
            'reason': AgentActionTriggerConstants.appCloseRuntimeTooLongReason,
            'user_message':
                'A acao nao foi executada no fechamento porque o tempo maximo configurado e maior que o limite permitido para encerrar o app.',
          },
        ),
      );
    }

    if (definition.policies.remote.canRunSavedAction) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action app-close trigger cannot run because the action is approved for remote execution.',
          code: AgentActionFailureCode.appCloseRemoteActionBlocked,
          context: {
            'trigger_id': trigger.id,
            'action_id': actionId,
            'reason': AgentActionTriggerConstants.appCloseRemoteActionBlockedReason,
            'user_message':
                'A acao nao foi executada no fechamento porque ela esta aprovada para execucao remota pelo hub.',
          },
        ),
      );
    }

    if (definition.policies.elevated.runElevated) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action app-close trigger cannot run because the action requires elevated execution.',
          code: AgentActionFailureCode.appCloseElevatedActionBlocked,
          context: {
            'trigger_id': trigger.id,
            'action_id': actionId,
            'reason': AgentActionTriggerConstants.appCloseElevatedActionBlockedReason,
            'user_message':
                'A acao nao foi executada no fechamento porque ela exige execucao elevada (UAC).',
          },
        ),
      );
    }

    return const Success(true);
  }

  Duration _delayUntil(DateTime nextRunAt) {
    final delay = nextRunAt.difference(_now());
    if (delay.isNegative) {
      return Duration.zero;
    }

    return delay;
  }

  void _cancelAllTimers() {
    for (final timer in _timersByTriggerId.values) {
      timer.cancel();
    }
    _timersByTriggerId.clear();
  }

  AgentActionSchedulerIssue _issueFor(
    String triggerId,
    Object failure,
  ) {
    if (failure is ActionFailure) {
      return AgentActionSchedulerIssue(
        triggerId: triggerId,
        message: AgentActionFailureDiagnosticsResolver.userMessage(failure),
        code: failure.code,
      );
    }

    return AgentActionSchedulerIssue(
      triggerId: triggerId,
      message: AgentActionFailureDiagnosticsResolver.userMessage(failure),
    );
  }

  static AgentActionSchedulerTimer _defaultTimerFactory(
    Duration delay,
    void Function() callback,
  ) {
    return _DartAgentActionSchedulerTimer(Timer(delay, callback));
  }
}

class _DartAgentActionSchedulerTimer implements AgentActionSchedulerTimer {
  const _DartAgentActionSchedulerTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
