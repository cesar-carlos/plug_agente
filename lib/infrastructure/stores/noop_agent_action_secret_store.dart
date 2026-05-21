import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

/// Placeholder store until action secrets are persisted in secure storage.
class NoopAgentActionSecretStore implements IAgentActionSecretStore {
  const NoopAgentActionSecretStore();

  @override
  bool get isAvailable => false;

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {}

  @override
  Future<String?> readSecret(String secretName) async => null;

  @override
  Future<void> deleteSecret(String secretName) async {}

  @override
  Future<bool> exists(String secretName) async => false;
}
