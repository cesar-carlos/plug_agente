import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:result_dart/result_dart.dart';

class FakeCommandLineActionAdapter implements AgentActionAdapter {
  FakeCommandLineActionAdapter({
    this.result,
  });

  final Result<AgentActionPreflight>? result;

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return result ??
        Success(
          AgentActionPreflight(
            actionType: type,
            canRun: definition.canRun,
          ),
        );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: 'cmd.exe /C ***',
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(definition);
  }
}

void main() {
  group('ValidateAgentActionDefinition', () {
    test('should validate definition through registered adapter', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().canRun, isTrue);
    });

    test('should reject empty action name before adapter validation', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: ' ',
          config: CommandLineActionConfig(command: 'dir'),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).context, containsPair('field', 'name'));
    });

    test('should reject invalid queue policy before adapter validation', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          config: CommandLineActionConfig(command: 'dir'),
          policies: AgentActionDefinitionPolicies(
            queue: AgentActionQueuePolicy(maxConcurrent: 0),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).context, containsPair('field', 'queue.maxConcurrent'));
    });

    test('should reject blank allowlist entries before adapter validation', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          config: CommandLineActionConfig(command: 'dir'),
          policies: AgentActionDefinitionPolicies(
            path: AgentActionPathPolicy(
              allowedWorkingDirectories: {' '},
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidPathPolicyReason),
      );
    });

    test('should reject invalid context json schema before adapter validation', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          config: CommandLineActionConfig(command: 'dir'),
          policies: AgentActionDefinitionPolicies(
            context: AgentActionContextPolicy(
              contextJsonSchema: {
                'type': 'not-a-json-schema-type',
              },
            ),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      final actionFailure = failure! as ActionValidationFailure;
      expect(
        actionFailure.context,
        containsPair('reason', AgentActionValidationConstants.invalidContextJsonSchemaDefinitionReason),
      );
      expect(actionFailure.context, containsPair('field', 'context.contextJsonSchema'));
    });

    test('should return unsupported type failure when adapter is missing', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        AgentActionDefinition(
          id: 'action-1',
          name: 'Developer action',
          config: DeveloperActionConfig.data7Executor(
            executorPath: const AgentActionPathReference(
              originalPath: r'C:\Data7\bin\Executor.exe',
            ),
            projectPath: const AgentActionPathReference(
              originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
            ),
            data7ConfigPath: const AgentActionPathReference(
              originalPath: r'C:\Data7\bin\Data7.Config',
            ),
            connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
            connectionLabel: 'Data7',
          ),
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should fail validation when referenced secret is missing', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
        secretPlaceholderResolver: AgentActionSecretPlaceholderResolver(
          secretStore: _FakeAgentActionSecretStore(existing: const {}),
        ),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Secret action',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: r'echo ${secret:api_token}',
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context,
        containsPair('reason', AgentActionGateConstants.secretUnavailableReason),
      );
    });

    test('should reject definition when queue policy exceeds deployment ceiling', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );
      final ceiling = AgentActionPolicyDefaults.maxConcurrentActions;

      final result = await useCase(
        AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          state: AgentActionState.active,
          config: const CommandLineActionConfig(command: 'dir'),
          policies: AgentActionDefinitionPolicies(
            queue: AgentActionQueuePolicy(maxConcurrent: ceiling + 1),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context['reason'],
        AgentActionValidationConstants.policyDeploymentCeilingExceededReason,
      );
      expect(failure.context['field'], 'queue.maxConcurrent');
    });

    test('should reject elevated action with retry maxAttempts greater than one', () async {
      final useCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(),
        ]),
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Elevated retry',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
          policies: AgentActionDefinitionPolicies(
            elevated: AgentActionElevatedPolicy(runElevated: true),
            retry: AgentActionRetryPolicy(maxAttempts: 2),
          ),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context['reason'],
        AgentActionValidationConstants.elevatedRetryNotAllowedReason,
      );
      expect(failure.context['field'], 'retry.maxAttempts');
    });
  });
}

class _FakeAgentActionSecretStore implements IAgentActionSecretStore {
  _FakeAgentActionSecretStore({required this.existing});

  final Set<String> existing;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {}

  @override
  Future<bool> exists(String secretName) async => existing.contains(secretName);

  @override
  Future<String?> readSecret(String secretName) async => existing.contains(secretName) ? 'value' : null;

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    existing.add(secretName);
  }
}
