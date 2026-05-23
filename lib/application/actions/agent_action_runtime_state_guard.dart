import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionRuntimeStateSnapshot {
  const AgentActionRuntimeStateSnapshot({
    required this.status,
    this.unavailableActionTypes = const {},
    this.reason,
  });

  final AgentActionSubsystemStatus status;
  final Set<AgentActionType> unavailableActionTypes;
  final String? reason;

  bool blocksType(AgentActionType type) {
    return status == AgentActionSubsystemStatus.degraded && unavailableActionTypes.contains(type);
  }
}

class AgentActionRuntimeStateGuard {
  AgentActionRuntimeStateGuard([FeatureFlags? featureFlags]) : _featureFlags = featureFlags;

  final FeatureFlags? _featureFlags;

  AgentActionRuntimeStateSnapshot _snapshot = const AgentActionRuntimeStateSnapshot(
    status: AgentActionSubsystemStatus.ready,
  );

  AgentActionRuntimeStateSnapshot get snapshot => _snapshot;

  bool get _maintenanceStrictModeEnabled =>
      _featureFlags?.enableAgentActionsMaintenanceStrictMode ?? false;

  void markReady() {
    _snapshot = const AgentActionRuntimeStateSnapshot(
      status: AgentActionSubsystemStatus.ready,
    );
  }

  void markStarting({String? reason}) {
    _snapshot = AgentActionRuntimeStateSnapshot(
      status: AgentActionSubsystemStatus.starting,
      reason: reason,
    );
  }

  void markDraining({String? reason}) {
    _snapshot = AgentActionRuntimeStateSnapshot(
      status: AgentActionSubsystemStatus.draining,
      reason: reason,
    );
  }

  void markMaintenance({String? reason}) {
    _snapshot = AgentActionRuntimeStateSnapshot(
      status: AgentActionSubsystemStatus.maintenance,
      reason: reason,
    );
  }

  void markDegraded({
    required Set<AgentActionType> unavailableActionTypes,
    String? reason,
  }) {
    _snapshot = AgentActionRuntimeStateSnapshot(
      status: AgentActionSubsystemStatus.degraded,
      unavailableActionTypes: unavailableActionTypes,
      reason: reason,
    );
  }

  void markDisabled({String? reason}) {
    _snapshot = AgentActionRuntimeStateSnapshot(
      status: AgentActionSubsystemStatus.disabled,
      reason: reason,
    );
  }

  Result<void> ensureCanAcceptExecution({
    required AgentActionExecutionRequest request,
    required AgentActionType actionType,
  }) {
    final current = _snapshot;
    return switch (current.status) {
      AgentActionSubsystemStatus.ready => const Success(unit),
      AgentActionSubsystemStatus.degraded =>
        current.blocksType(actionType)
            ? Failure(_failureFor(current, request: request, actionType: actionType))
            : const Success(unit),
      AgentActionSubsystemStatus.maintenance =>
        request.source == AgentActionRequestSource.localUi && !_maintenanceStrictModeEnabled
            ? const Success(unit)
            : Failure(_failureFor(current, request: request, actionType: actionType)),
      AgentActionSubsystemStatus.draining =>
        request.triggerType == AgentActionTriggerType.appClose &&
                request.source == AgentActionRequestSource.appLifecycle
            ? const Success(unit)
            : Failure(_failureFor(current, request: request, actionType: actionType)),
      AgentActionSubsystemStatus.starting ||
      AgentActionSubsystemStatus.disabled => Failure(_failureFor(current, request: request, actionType: actionType)),
    };
  }

  ActionAuthorizationFailure _failureFor(
    AgentActionRuntimeStateSnapshot snapshot, {
    required AgentActionExecutionRequest request,
    required AgentActionType actionType,
  }) {
    final reason = _reasonFor(snapshot.status);
    return ActionAuthorizationFailure.withContext(
      message: 'Agent actions subsystem is not ready to accept this execution.',
      code: _codeFor(snapshot.status),
      context: {
        'status': snapshot.status.name,
        'source': request.source.name,
        'action_type': actionType.name,
        'reason': reason,
        if (snapshot.status == AgentActionSubsystemStatus.starting ||
            snapshot.status == AgentActionSubsystemStatus.draining)
          'rpc_error_code': RpcErrorCode.agentActionsTemporarilyUnavailable,
        if (snapshot.reason != null) 'detail': snapshot.reason,
        if (snapshot.unavailableActionTypes.isNotEmpty)
          'unavailable_action_types': snapshot.unavailableActionTypes.map((type) => type.name).toList(growable: false),
        'user_message': _userMessageForMaintenanceBlock(
          snapshot.status,
          request.source,
        ),
      },
    );
  }

  String _codeFor(AgentActionSubsystemStatus status) {
    return switch (status) {
      AgentActionSubsystemStatus.starting => AgentActionFailureCode.subsystemStarting,
      AgentActionSubsystemStatus.draining => AgentActionFailureCode.subsystemDraining,
      AgentActionSubsystemStatus.maintenance => AgentActionFailureCode.maintenanceMode,
      AgentActionSubsystemStatus.degraded => AgentActionFailureCode.subsystemDegraded,
      AgentActionSubsystemStatus.disabled => AgentActionFailureCode.featureDisabled,
      AgentActionSubsystemStatus.ready => AgentActionFailureCode.subsystemReady,
    };
  }

  String _reasonFor(AgentActionSubsystemStatus status) {
    return switch (status) {
      AgentActionSubsystemStatus.starting => AgentActionRuntimeStateConstants.agentActionsStartingReason,
      AgentActionSubsystemStatus.draining => AgentActionRuntimeStateConstants.agentActionsDrainingReason,
      AgentActionSubsystemStatus.maintenance => AgentActionGateConstants.maintenanceModeReason,
      AgentActionSubsystemStatus.degraded => AgentActionRuntimeStateConstants.agentActionsDegradedReason,
      AgentActionSubsystemStatus.disabled => AgentActionGateConstants.featureDisabledReason,
      AgentActionSubsystemStatus.ready => AgentActionRuntimeStateConstants.subsystemReadyReason,
    };
  }

  String _userMessageFor(AgentActionSubsystemStatus status) {
    return switch (status) {
      AgentActionSubsystemStatus.starting =>
        'As acoes do agente ainda estao inicializando. Tente novamente em instantes.',
      AgentActionSubsystemStatus.draining =>
        'O Plug Agente esta finalizando operacoes e nao aceita novas execucoes agora.',
      AgentActionSubsystemStatus.maintenance =>
        'As execucoes remotas e agendadas estao bloqueadas pelo modo de manutencao.',
      AgentActionSubsystemStatus.degraded => 'O executor desta acao esta temporariamente indisponivel.',
      AgentActionSubsystemStatus.disabled => 'As acoes do agente estao desativadas neste ambiente.',
      AgentActionSubsystemStatus.ready => 'As acoes do agente estao prontas.',
    };
  }

  String _userMessageForMaintenanceBlock(
    AgentActionSubsystemStatus status,
    AgentActionRequestSource source,
  ) {
    if (status == AgentActionSubsystemStatus.maintenance &&
        source == AgentActionRequestSource.localUi &&
        _maintenanceStrictModeEnabled) {
      return 'Todas as execucoes estao bloqueadas pelo modo de manutencao, incluindo execucao manual.';
    }

    return _userMessageFor(status);
  }
}
