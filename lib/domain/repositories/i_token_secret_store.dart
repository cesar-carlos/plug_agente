abstract class ITokenSecretStore {
  Future<void> saveSecret(String tokenId, String tokenValue);

  Future<String?> readSecret(String tokenId);

  Future<void> deleteSecret(String tokenId);
}
