import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';

abstract interface class IHubAuthSecretStore {
  bool get isAvailable;

  Future<void> saveSecrets(String configId, HubAuthSecrets secrets);

  Future<HubAuthSecrets> readSecrets(String configId);

  Future<void> deleteSecrets(String configId);
}
