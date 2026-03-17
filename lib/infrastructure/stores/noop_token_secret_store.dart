import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

class NoopTokenSecretStore implements ITokenSecretStore {
  @override
  Future<void> saveSecret(String tokenId, String tokenValue) async {}

  @override
  Future<String?> readSecret(String tokenId) async => null;

  @override
  Future<void> deleteSecret(String tokenId) async {}
}
