import 'package:plug_agente/domain/value_objects/config_row_legacy_secrets.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IOdbcCredentialStore {
  Future<Result<OdbcCredentialSecrets>> readCredentials(String configId);

  Future<Result<Map<String, OdbcCredentialSecrets>>> readCredentialsForLegacyRows(
    List<ConfigRowLegacySecrets> rows,
  );

  Future<Result<void>> deleteAllSecrets(String configId);
}
