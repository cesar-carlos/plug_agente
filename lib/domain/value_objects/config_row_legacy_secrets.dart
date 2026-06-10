import 'package:plug_agente/core/utils/odbc_connection_string_secrets.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';

class ConfigRowLegacySecrets {
  const ConfigRowLegacySecrets({
    required this.configId,
    this.authToken,
    this.refreshToken,
    this.authPassword,
    this.authUsername,
    this.odbcPassword,
    this.connectionString,
  });

  final String configId;
  final String? authToken;
  final String? refreshToken;
  final String? authPassword;
  final String? authUsername;
  final String? odbcPassword;
  final String? connectionString;

  HubAuthSecrets get hubAuthSecrets {
    return HubAuthSecrets(
      authToken: authToken,
      refreshToken: refreshToken,
      authPassword: authPassword,
    );
  }

  OdbcCredentialSecrets get odbcLegacySecrets {
    final normalizedPassword = _normalize(odbcPassword);
    return OdbcCredentialSecrets(
      password:
          normalizedPassword ??
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            connectionString ?? '',
          ),
    );
  }

  String? get normalizedAuthUsername => _normalize(authUsername);

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
