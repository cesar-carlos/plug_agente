import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

class FlutterSecureTokenSecretStore implements ITokenSecretStore {
  FlutterSecureTokenSecretStore({
    FlutterSecureStorage? secureStorage,
    this.keyPrefix = 'client_token_secret_',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final String keyPrefix;

  @override
  bool get isAvailable => true;

  String _keyFor(String secretKey) => '$keyPrefix$secretKey';

  @override
  Future<void> saveSecret(String secretKey, String tokenValue) async {
    await _secureStorage.write(key: _keyFor(secretKey), value: tokenValue);
  }

  @override
  Future<String?> readSecret(String secretKey) async {
    return _secureStorage.read(key: _keyFor(secretKey));
  }

  @override
  Future<void> deleteSecret(String secretKey) async {
    await _secureStorage.delete(key: _keyFor(secretKey));
  }
}
