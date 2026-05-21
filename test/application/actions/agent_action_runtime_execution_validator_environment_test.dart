import 'package:checks/checks.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_execution_validator.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:test/test.dart';

void main() {
  test('should reject context path when injection mode is environment', () {
    const validator = AgentActionRuntimeExecutionValidator();
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Env injection',
      config: CommandLineActionConfig(command: 'echo ok'),
      policies: AgentActionDefinitionPolicies(
        context: AgentActionContextPolicy(
          injectionMode: AgentActionContextInjectionMode.environment,
        ),
      ),
    );

    final result = validator.validateForExecution(
      definition: definition,
      request: AgentActionExecutionRequest(
        actionId: definition.id,
        source: AgentActionRequestSource.localUi,
        contextPath: r'C:\ctx.json',
      ),
    );

    check(result.isError()).isTrue();
    final failure = result.exceptionOrNull()! as ActionValidationFailure;
    check(failure.context['reason']).equals(
      AgentActionValidationConstants.contextInjectionRejectsFileReason,
    );
  });
}
