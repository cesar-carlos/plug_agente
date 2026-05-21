import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

class FlutterSecureAgentActionSecretStore implements IAgentActionSecretStore {
  FlutterSecureAgentActionSecretStore({
    FlutterSecureStorage? secureStorage,
    this.keyPrefix = 'agent_action_secret_',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final String keyPrefix;

  @override
  bool get isAvailable => true;

  String _keyFor(String secretName) => '$keyPrefix$secretName';

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    await _secureStorage.write(key: _keyFor(secretName), value: secretValue);
  }

  @override
  Future<String?> readSecret(String secretName) async {
    return _secureStorage.read(key: _keyFor(secretName));
  }

  @override
  Future<void> deleteSecret(String secretName) async {
    await _secureStorage.delete(key: _keyFor(secretName));
  }

  @override
  Future<bool> exists(String secretName) async {
    final value = await readSecret(secretName);
    return value != null && value.isNotEmpty;
  }
}
