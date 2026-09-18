import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_command_line_policy_validator.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  const validator = AgentActionCommandLinePolicyValidator();
  const definition = AgentActionDefinition(
    id: 'command-line',
    name: 'Command line',
    state: AgentActionState.active,
    config: CommandLineActionConfig(command: 'echo ok'),
  );

  test('allows manual local command-line execution', () {
    final result = validator.validateExecution(
      definition: definition,
      request: const AgentActionExecutionRequest(
        actionId: 'command-line',
        source: AgentActionRequestSource.localUi,
      ),
    );
    expect(result.isSuccess(), isTrue);
  });

  test('rejects non-local command-line execution with a stable failure', () {
    final result = validator.validateExecution(
      definition: definition,
      request: const AgentActionExecutionRequest(
        actionId: 'command-line',
        source: AgentActionRequestSource.scheduler,
      ),
    );
    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
    expect((result.exceptionOrNull()! as ActionFailure).code, AgentActionFailureCode.commandLineLocalOnly);
  });

  test('rejects secret placeholders in free-form command definitions', () {
    final result = validator.validateDefinition(
      definition.copyWith(config: const CommandLineActionConfig(command: r'echo ${secret:api_key}')),
    );
    expect(result.isError(), isTrue);
    expect(
      (result.exceptionOrNull()! as ActionFailure).code,
      AgentActionFailureCode.commandLineSecretPlaceholderForbidden,
    );
  });
}
