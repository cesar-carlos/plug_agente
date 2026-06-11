import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_actions_local_operation_policy.dart';
import 'package:plug_agente/application/actions/i_action_command_safety_assessor.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

class _AllowAssessor implements IActionCommandSafetyAssessor {
  const _AllowAssessor();

  @override
  AgentActionDangerousCommandAssessment assessForLocalRun({
    required String command,
    required bool warnModeEnabled,
  }) {
    return const AgentActionDangerousCommandAssessment.allow();
  }
}

void main() {
  const policy = AgentActionsLocalOperationPolicy(commandSafetyAssessor: _AllowAssessor());

  test('canRunDefinition requires feature enabled and idle runner', () {
    const definition = AgentActionDefinition(
      id: 'a1',
      name: 'Run',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    expect(
      policy.canRunDefinition(
        definition: definition,
        isFeatureEnabled: true,
        isRunning: false,
        allowsLocalManualOperation: true,
      ),
      isTrue,
    );
    expect(
      policy.canRunDefinition(
        definition: definition,
        isFeatureEnabled: false,
        isRunning: false,
        allowsLocalManualOperation: true,
      ),
      isFalse,
    );
  });

  test('assessDangerousCommandForRun delegates to assessor for command line', () {
    const definition = AgentActionDefinition(
      id: 'a1',
      name: 'Run',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    final assessment = policy.assessDangerousCommandForRun(
      definition: definition,
      warnModeEnabled: true,
    );

    expect(assessment.requiresConfirmation, isFalse);
  });
}
