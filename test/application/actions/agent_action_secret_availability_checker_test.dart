import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

void main() {
  group('AgentActionSecretAvailabilityChecker', () {
    test('should report referenced secrets without missing names when store is unavailable', () async {
      const checker = AgentActionSecretAvailabilityChecker();
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run',
        config: CommandLineActionConfig(command: r'echo ${secret:db_password}'),
      );

      final report = await checker.check(definition);

      expect(report.referencedSecretNames, {'db_password'});
      expect(report.missingSecretNames, isEmpty);
      expect(report.storeAvailable, isFalse);
    });

    test('should report missing secrets when store is available but secret is absent', () async {
      final checker = AgentActionSecretAvailabilityChecker(
        secretStore: _FakeAgentActionSecretStore(existing: {'other'}),
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run',
        config: CommandLineActionConfig(command: r'echo ${secret:db_password}'),
      );

      final report = await checker.check(definition);

      expect(report.missingSecretNames, {'db_password'});
      expect(report.storeAvailable, isTrue);
    });
  });
}

class _FakeAgentActionSecretStore implements IAgentActionSecretStore {
  _FakeAgentActionSecretStore({required this.existing});

  final Set<String> existing;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    existing.remove(secretName);
  }

  @override
  Future<String?> readSecret(String secretName) async {
    return existing.contains(secretName) ? 'configured' : null;
  }

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    existing.add(secretName);
  }

  @override
  Future<bool> exists(String secretName) async => existing.contains(secretName);
}
