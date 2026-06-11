part of '../agent_actions_provider.dart';

extension AgentActionsProviderCapabilities on AgentActionsProvider {
  bool canRunDefinition(AgentActionDefinition definition) {
    return _localOperationPolicy.canRunDefinition(
      definition: definition,
      isFeatureEnabled: isFeatureEnabled,
      isRunning: isRunning,
      allowsLocalManualOperation: _runtimeSurfaceCoordinator.allowsLocalManualOperation(definition.type),
    );
  }

  bool canTestDefinition(AgentActionDefinition definition) {
    return _localOperationPolicy.canTestDefinition(
      isFeatureEnabled: isFeatureEnabled,
      isTesting: isTesting,
      allowsLocalManualOperation: _runtimeSurfaceCoordinator.allowsLocalManualOperation(definition.type),
    );
  }

  bool canDeleteDefinition(AgentActionDefinition definition) {
    return _definitionsController.canDeleteDefinition(
      definition: definition,
      isFeatureEnabled: isFeatureEnabled,
      hasActiveExecution: _executionsController.hasActiveExecutionForDefinition(definition.id),
    );
  }

  AgentActionDangerousCommandAssessment assessDangerousCommandForRun(AgentActionDefinition definition) {
    return _localOperationPolicy.assessDangerousCommandForRun(
      definition: definition,
      warnModeEnabled: isDangerousCommandWarnModeEnabled,
    );
  }

  void reportDangerousCommandBlocked(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  bool get canRunSelected {
    final definition = selectedDefinition;
    return definition != null && canRunDefinition(definition);
  }

  bool get canTestSelected {
    final definition = selectedDefinition;
    return definition != null && canTestDefinition(definition);
  }

  bool get canDeleteSelected {
    final definition = selectedDefinition;
    return definition != null && canDeleteDefinition(definition);
  }
}
