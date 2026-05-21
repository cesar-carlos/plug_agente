import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

void main() {
  group('AgentActionSecretPlaceholderResolver', () {
    test('should return text unchanged when there are no placeholders', () async {
      const resolver = AgentActionSecretPlaceholderResolver();

      final result = await resolver.resolveText(
        text: 'echo hello',
        actionId: 'action-1',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 'echo hello');
    });

    test('should fail when placeholders exist but store is unavailable', () async {
      final resolver = AgentActionSecretPlaceholderResolver(
        secretStore: NoopAgentActionSecretStoreForTests(),
      );

      final result = await resolver.resolveText(
        text: r'echo ${secret:api_token}',
        actionId: 'action-1',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.secretUnavailable);
      expect(
        failure.context,
        containsPair('reason', AgentActionGateConstants.secretUnavailableReason),
      );
      expect(failure.context['missing_secrets'], ['api_token']);
    });

    test('should substitute placeholders when secrets exist in store', () async {
      final resolver = AgentActionSecretPlaceholderResolver(
        secretStore: _InMemoryAgentActionSecretStore(
          values: {'api_token': 's3cret'},
        ),
      );

      final result = await resolver.resolveText(
        text: r'echo ${secret:api_token} done',
        actionId: 'action-1',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 'echo s3cret done');
    });

    test('should resolve executable arguments for execution', () async {
      final resolver = AgentActionSecretPlaceholderResolver(
        secretStore: _InMemoryAgentActionSecretStore(
          values: {'api_token': 'resolved-token'},
        ),
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run',
        config: ExecutableActionConfig(
          executablePath: AgentActionPathReference(originalPath: r'C:\tools\app.exe'),
          arguments: <String>['--token', r'${secret:api_token}'],
        ),
      );

      final result = await resolver.resolveForExecution(definition);

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow().config as ExecutableActionConfig;
      expect(config.arguments, <String>['--token', 'resolved-token']);
    });

    test('should resolve command line definition for execution', () async {
      final resolver = AgentActionSecretPlaceholderResolver(
        secretStore: _InMemoryAgentActionSecretStore(
          values: {'db_password': 'p@ss'},
        ),
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run',
        config: CommandLineActionConfig(command: r'echo ${secret:db_password}'),
      );

      final result = await resolver.resolveForExecution(definition);

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow().config as CommandLineActionConfig;
      expect(config.command, 'echo p@ss');
    });
  });
}

class NoopAgentActionSecretStoreForTests implements IAgentActionSecretStore {
  @override
  bool get isAvailable => false;

  @override
  Future<void> deleteSecret(String secretName) async {}

  @override
  Future<String?> readSecret(String secretName) async => null;

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {}

  @override
  Future<bool> exists(String secretName) async => false;
}

class _InMemoryAgentActionSecretStore implements IAgentActionSecretStore {
  _InMemoryAgentActionSecretStore({required this.values});

  final Map<String, String> values;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    values.remove(secretName);
  }

  @override
  Future<String?> readSecret(String secretName) async => values[secretName];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    values[secretName] = secretValue;
  }

  @override
  Future<bool> exists(String secretName) async {
    final value = await readSecret(secretName);
    return value != null && value.isNotEmpty;
  }
}
