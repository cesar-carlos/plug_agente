import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

void main() {
  group('DeleteAgentActionSecret', () {
    test('should delete secret when store is available', () async {
      final store = _InMemoryAgentActionSecretStore(
        initialValues: {'api_token': 'value'},
      );
      final useCase = DeleteAgentActionSecret(store);

      final result = await useCase('api_token');

      expect(result.isSuccess(), isTrue);
      expect(await store.exists('api_token'), isFalse);
    });

    test('should fail when store is unavailable', () async {
      const useCase = DeleteAgentActionSecret(_UnavailableAgentActionSecretStore());

      final result = await useCase('api_token');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });
  });
}

class _InMemoryAgentActionSecretStore implements IAgentActionSecretStore {
  _InMemoryAgentActionSecretStore({Map<String, String>? initialValues})
    : _values = Map<String, String>.from(initialValues ?? <String, String>{});

  final Map<String, String> _values;

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
