import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';

/// Assesses command-line actions for dangerous patterns before local runs.
abstract interface class IActionCommandSafetyAssessor {
  AgentActionDangerousCommandAssessment assessForLocalRun({
    required String command,
    required bool warnModeEnabled,
  });
}
