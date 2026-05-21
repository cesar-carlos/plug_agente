import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_agent_action_secret_store.dart';

void main() {
  group('AgentActionSecretReferenceFingerprinter', () {
    test('should return empty map when definition has no secret placeholders', () async {
      const fingerprinter = AgentActionSecretReferenceFingerprinter(NoopAgentActionSecretStore());
      const definition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'echo hi'),
      );

      expect(await fingerprinter.fingerprintsFor(definition), isEmpty);
    });

    test('should fingerprint secret values without exposing them', () async {
      final store = _InMemoryAgentActionSecretStore();
      await store.saveSecret('smtp', 'first-value');
      final fingerprinter = AgentActionSecretReferenceFingerprinter(store);
      const definition = AgentActionDefinition(
        id: 'a1',
        name: 'Email',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'curl --user ${secret:smtp}'),
      );

      final first = await fingerprinter.fingerprintsFor(definition);
      expect(first['smtp'], startsWith('sha256:'));

      await store.saveSecret('smtp', 'rotated-value');
      final second = await fingerprinter.fingerprintsFor(definition);
      expect(second['smtp'], isNot(equals(first['smtp'])));
    });

    test('should mark missing secrets without reading values', () async {
      const fingerprinter = AgentActionSecretReferenceFingerprinter(NoopAgentActionSecretStore());
      const definition = AgentActionDefinition(
        id: 'a1',
        name: 'A',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:missing}'),
      );

      final fingerprints = await fingerprinter.fingerprintsFor(definition);
      expect(fingerprints['missing'], AgentActionSecretReferenceFingerprinter.missingFingerprint);
    });
  });
}

class _InMemoryAgentActionSecretStore implements IAgentActionSecretStore {
  final Map<String, String> _secrets = <String, String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    _secrets.remove(secretName);
  }

  @override
  Future<bool> exists(String secretName) async => _secrets.containsKey(secretName);

  @override
  Future<String?> readSecret(String secretName) async => _secrets[secretName];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    _secrets[secretName] = secretValue;
  }
}
