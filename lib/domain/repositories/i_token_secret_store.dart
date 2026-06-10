abstract class ITokenSecretStore {
  bool get isAvailable;

  Future<void> saveSecret(String secretKey, String tokenValue);

  Future<String?> readSecret(String secretKey);

  Future<void> deleteSecret(String secretKey);
}
