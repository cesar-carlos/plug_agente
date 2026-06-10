import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

class NoopTokenSecretStore implements ITokenSecretStore {
  @override
  bool get isAvailable => false;

  @override
  Future<void> saveSecret(String secretKey, String tokenValue) async {}

  @override
  Future<String?> readSecret(String secretKey) async => null;

  @override
  Future<void> deleteSecret(String secretKey) async {}
}
