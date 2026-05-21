/// Persists action-scoped secrets referenced by `${secret:name}` placeholders.
abstract class IAgentActionSecretStore {
  bool get isAvailable;

  Future<void> saveSecret(String secretName, String secretValue);

  Future<String?> readSecret(String secretName);

  Future<void> deleteSecret(String secretName);

  Future<bool> exists(String secretName);
}
