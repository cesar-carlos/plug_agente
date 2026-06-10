import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/stores/batch_secret_store_mixin.dart';

class FlutterSecureOdbcCredentialSecretStore
    with BatchOdbcCredentialSecretStoreMixin
    implements IOdbcCredentialSecretStore {
  FlutterSecureOdbcCredentialSecretStore({
    FlutterSecureStorage? secureStorage,
    this.keyPrefix = 'odbc_credential_secret_',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final String keyPrefix;

  static const String _passwordSuffix = 'password';

  @override
  bool get isAvailable => true;

  String _keyFor(String configId, String suffix) => '$keyPrefix${configId}_$suffix';

  @override
  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets) async {
    await _writeNullable(
      _keyFor(configId, _passwordSuffix),
      secrets.password,
    );
  }

  @override
  Future<OdbcCredentialSecrets> readSecrets(String configId) async {
    return OdbcCredentialSecrets(
      password: await _secureStorage.read(
        key: _keyFor(configId, _passwordSuffix),
      ),
    );
  }

  @override
  Future<void> deleteSecrets(String configId) async {
    await _secureStorage.delete(key: _keyFor(configId, _passwordSuffix));
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
