import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

class FlutterSecureTokenSecretStore implements ITokenSecretStore {
  FlutterSecureTokenSecretStore({
    FlutterSecureStorage? secureStorage,
    this.keyPrefix = 'client_token_secret_',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final String keyPrefix;

  String _keyFor(String tokenId) => '$keyPrefix$tokenId';

  @override
  Future<void> saveSecret(String tokenId, String tokenValue) async {
    await _secureStorage.write(key: _keyFor(tokenId), value: tokenValue);
  }

  @override
  Future<String?> readSecret(String tokenId) async {
    return _secureStorage.read(key: _keyFor(tokenId));
  }

  @override
  Future<void> deleteSecret(String tokenId) async {
    await _secureStorage.delete(key: _keyFor(tokenId));
  }
}
