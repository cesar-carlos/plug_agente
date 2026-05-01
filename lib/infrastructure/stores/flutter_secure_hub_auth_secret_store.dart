import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';

class FlutterSecureHubAuthSecretStore implements IHubAuthSecretStore {
  FlutterSecureHubAuthSecretStore({
    FlutterSecureStorage? secureStorage,
    this.keyPrefix = 'hub_auth_secret_',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final String keyPrefix;

  static const String _authTokenSuffix = 'auth_token';
  static const String _refreshTokenSuffix = 'refresh_token';
  static const String _authPasswordSuffix = 'auth_password';

  @override
  bool get isAvailable => true;

  String _keyFor(String configId, String suffix) => '$keyPrefix${configId}_$suffix';

  @override
  Future<void> saveSecrets(String configId, HubAuthSecrets secrets) async {
    await _writeNullable(
      _keyFor(configId, _authTokenSuffix),
      secrets.authToken,
    );
    await _writeNullable(
      _keyFor(configId, _refreshTokenSuffix),
      secrets.refreshToken,
    );
    await _writeNullable(
      _keyFor(configId, _authPasswordSuffix),
      secrets.authPassword,
    );
  }

  @override
  Future<HubAuthSecrets> readSecrets(String configId) async {
    return HubAuthSecrets(
      authToken: await _secureStorage.read(
        key: _keyFor(configId, _authTokenSuffix),
      ),
      refreshToken: await _secureStorage.read(
        key: _keyFor(configId, _refreshTokenSuffix),
      ),
      authPassword: await _secureStorage.read(
        key: _keyFor(configId, _authPasswordSuffix),
      ),
    );
  }

  @override
  Future<void> deleteSecrets(String configId) async {
    await _secureStorage.delete(key: _keyFor(configId, _authTokenSuffix));
    await _secureStorage.delete(key: _keyFor(configId, _refreshTokenSuffix));
    await _secureStorage.delete(key: _keyFor(configId, _authPasswordSuffix));
  }

  Future<void> _writeNullable(String key, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStorage.delete(key: key);
      return;
    }
    await _secureStorage.write(key: key, value: trimmed);
  }
}
