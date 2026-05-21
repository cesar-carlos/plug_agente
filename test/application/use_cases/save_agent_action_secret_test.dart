import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

void main() {
  group('SaveAgentActionSecret', () {
    test('should save secret when store is available', () async {
      final store = _InMemoryAgentActionSecretStore();
      final useCase = SaveAgentActionSecret(store);

      final result = await useCase(
        secretName: 'api_token',
        secretValue: 'secret-value',
      );

      expect(result.isSuccess(), isTrue);
      expect(await store.readSecret('api_token'), 'secret-value');
    });

    test('should fail when store is unavailable', () async {
      const useCase = SaveAgentActionSecret(_UnavailableAgentActionSecretStore());

      final result = await useCase(
        secretName: 'api_token',
        secretValue: 'secret-value',
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });
  });
}

class _InMemoryAgentActionSecretStore implements IAgentActionSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    _values.remove(secretName);
  }

  @override
  Future<bool> exists(String secretName) async {
    final value = await readSecret(secretName);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<String?> readSecret(String secretName) async => _values[secretName];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    _values[secretName] = secretValue;
  }
}

class _UnavailableAgentActionSecretStore implements IAgentActionSecretStore {
  const _UnavailableAgentActionSecretStore();

  @override
  bool get isAvailable => false;

  @override
  Future<void> deleteSecret(String secretName) async {}

  @override
  Future<bool> exists(String secretName) async => false;

  @override
  Future<String?> readSecret(String secretName) async => null;

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {}
}
