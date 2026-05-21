import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_execution_validator.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  group('AgentActionRuntimeExecutionValidator', () {
    const validator = AgentActionRuntimeExecutionValidator();

    test('should require context path when injection mode is file', () {
      final result = validator.validateForExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo hi'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              injectionMode: AgentActionContextInjectionMode.file,
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.contextInjectionRequiresFileReason),
      );
    });

    test('should reject runtime parameters outside configured schema', () {
      final result = validator.validateForExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo hi'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              runtimeParameterSchema: {
                'type': 'object',
                'required': ['jobId'],
                'properties': {
                  'jobId': {'type': 'string'},
                },
              },
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {'jobId': 42},
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.runtimeParametersSchemaMismatchReason),
      );
    });

    test('should require runtime stdin payload when injection mode is stdin', () {
      final result = validator.validateForExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo hi'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              injectionMode: AgentActionContextInjectionMode.stdin,
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.contextInjectionRequiresStdinPayloadReason),
      );
    });

    test('should accept runtime parameters matching schema', () {
      final result = validator.validateForExecution(
        definition: const AgentActionDefinition(
          id: 'action-1',
          name: 'Test',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'echo hi'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              runtimeParameterSchema: {
                'type': 'object',
                'required': ['jobId'],
                'properties': {
                  'jobId': {'type': 'string'},
                },
              },
            ),
          ),
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {'jobId': 'batch-1'},
        ),
      );

      expect(result.isSuccess(), isTrue);
    });
  });
}
