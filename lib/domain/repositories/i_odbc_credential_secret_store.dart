import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';

abstract interface class IOdbcCredentialSecretStore {
  bool get isAvailable;

  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets);

  Future<OdbcCredentialSecrets> readSecrets(String configId);

  Future<Map<String, OdbcCredentialSecrets>> readSecretsForConfigIds(
    Iterable<String> configIds,
  );

  Future<void> deleteSecrets(String configId);
}
