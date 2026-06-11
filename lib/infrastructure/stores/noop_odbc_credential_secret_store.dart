import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/stores/batch_secret_store_mixin.dart';

class NoopOdbcCredentialSecretStore with BatchOdbcCredentialSecretStoreMixin implements IOdbcCredentialSecretStore {
  @override
  bool get isAvailable => false;

  @override
  Future<void> deleteSecrets(String configId) async {}

  @override
  Future<OdbcCredentialSecrets> readSecrets(String configId) async => const OdbcCredentialSecrets();

  @override
  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets) async {}
}
