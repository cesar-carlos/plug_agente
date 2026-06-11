import 'package:plug_agente/application/actions/i_action_command_safety_assessor.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

/// Local manual run/test eligibility and dangerous-command assessment.
final class AgentActionsLocalOperationPolicy {
  const AgentActionsLocalOperationPolicy({
    required IActionCommandSafetyAssessor commandSafetyAssessor,
  }) : _commandSafetyAssessor = commandSafetyAssessor;

  final IActionCommandSafetyAssessor _commandSafetyAssessor;

  bool canRunDefinition({
    required AgentActionDefinition definition,
    required bool isFeatureEnabled,
    required bool isRunning,
    required bool allowsLocalManualOperation,
  }) {
    return isFeatureEnabled && !isRunning && definition.canRun && allowsLocalManualOperation;
  }

  bool canTestDefinition({
    required bool isFeatureEnabled,
    required bool isTesting,
    required bool allowsLocalManualOperation,
  }) {
    return isFeatureEnabled && !isTesting && allowsLocalManualOperation;
  }

  AgentActionDangerousCommandAssessment assessDangerousCommandForRun({
    required AgentActionDefinition definition,
    required bool warnModeEnabled,
  }) {
    if (definition.type != AgentActionType.commandLine) {
      return const AgentActionDangerousCommandAssessment.allow();
    }

    final config = definition.config;
    if (config is! CommandLineActionConfig) {
      return const AgentActionDangerousCommandAssessment.allow();
    }

    return _commandSafetyAssessor.assessForLocalRun(
      command: config.command,
      warnModeEnabled: warnModeEnabled,
    );
  }
}
