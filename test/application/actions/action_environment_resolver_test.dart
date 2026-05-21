import 'package:checks/checks.dart';
import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:test/test.dart';

void main() {
  group('ActionEnvironmentResolver', () {
    test('should reject invalid variable names on validatePolicy', () {
      const resolver = ActionEnvironmentResolver();

      final failure = resolver.validatePolicy(
        actionId: 'action-1',
        policy: const AgentActionEnvironmentPolicy(
          variables: {'bad-name': 'value'},
        ),
      );

      check(failure).isNotNull();
      check(failure!.context['reason']).equals(
        AgentActionValidationConstants.invalidEnvironmentVariableNameReason,
      );
    });

    test('should resolve policy variables and runtime injection with secrets', () async {
      final store = _FakeSecretStore(secrets: {'api_key': 'secret-value'});
      final resolver = ActionEnvironmentResolver(
        secretPlaceholderResolver: AgentActionSecretPlaceholderResolver(secretStore: store),
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Env action',
        config: CommandLineActionConfig(command: 'echo ok'),
        policies: AgentActionDefinitionPolicies(
          context: AgentActionContextPolicy(
            injectionMode: AgentActionContextInjectionMode.environment,
          ),
          environment: AgentActionEnvironmentPolicy(
            allowedVariableNames: {'PLUG_STATIC', 'PLUG_RUNTIME'},
            variables: {
              'PLUG_STATIC': r'prefix-${secret:api_key}',
            },
          ),
        ),
      );

      final result = await resolver.resolveForProcess(
        definition: definition,
        request: AgentActionExecutionRequest(
          actionId: definition.id,
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {
            'PLUG_RUNTIME': 'from-runtime',
          },
        ),
      );

      check(result.isSuccess()).isTrue();
      final environment = result.getOrThrow();
      check(environment['PLUG_STATIC']).equals('prefix-secret-value');
      check(environment['PLUG_RUNTIME']).equals('from-runtime');
    });

    test('should reject runtime variable outside allowlist', () async {
      const resolver = ActionEnvironmentResolver();
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Env action',
        config: CommandLineActionConfig(command: 'echo ok'),
        policies: AgentActionDefinitionPolicies(
          context: AgentActionContextPolicy(
            injectionMode: AgentActionContextInjectionMode.environment,
          ),
          environment: AgentActionEnvironmentPolicy(
            allowedVariableNames: {'ALLOWED_ONLY'},
          ),
        ),
      );

      final result = await resolver.resolveForProcess(
        definition: definition,
        request: AgentActionExecutionRequest(
          actionId: definition.id,
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {
            'DENIED': 'value',
          },
        ),
      );

      check(result.isError()).isTrue();
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      check(failure.context['reason']).equals(
        AgentActionValidationConstants.environmentVariableNotAllowedReason,
      );
    });
  });
}

class _FakeSecretStore implements IAgentActionSecretStore {
  _FakeSecretStore({required Map<String, String> secrets}) : _secrets = Map<String, String>.from(secrets);

  final Map<String, String> _secrets;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> exists(String name) async => _secrets.containsKey(name);

  @override
  Future<String?> readSecret(String name) async => _secrets[name];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    _secrets[secretName] = secretValue;
  }

  @override
  Future<void> deleteSecret(String secretName) async {
    _secrets.remove(secretName);
  }
}
