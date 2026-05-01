import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';

class NoopHubAuthSecretStore implements IHubAuthSecretStore {
  @override
  bool get isAvailable => false;

  @override
  Future<void> deleteSecrets(String configId) async {}

  @override
  Future<HubAuthSecrets> readSecrets(String configId) async => const HubAuthSecrets();

  @override
  Future<void> saveSecrets(String configId, HubAuthSecrets secrets) async {}
}
