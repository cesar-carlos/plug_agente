import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

final class SecureStorageHealthSectionBuilder {
  const SecureStorageHealthSectionBuilder({
    IOdbcCredentialSecretStore? odbcCredentialSecretStore,
    IHubAuthSecretStore? hubAuthSecretStore,
    ITokenSecretStore? tokenSecretStore,
  }) : _odbcCredentialSecretStore = odbcCredentialSecretStore,
       _hubAuthSecretStore = hubAuthSecretStore,
       _tokenSecretStore = tokenSecretStore;

  final IOdbcCredentialSecretStore? _odbcCredentialSecretStore;
  final IHubAuthSecretStore? _hubAuthSecretStore;
  final ITokenSecretStore? _tokenSecretStore;

  Map<String, Object?>? build() {
    final odbcStore = _odbcCredentialSecretStore;
    final hubAuthStore = _hubAuthSecretStore;
    final tokenStore = _tokenSecretStore;
    if (odbcStore == null && hubAuthStore == null && tokenStore == null) {
      return null;
    }

    final odbcAvailable = odbcStore?.isAvailable ?? false;
    final hubAuthAvailable = hubAuthStore?.isAvailable ?? false;
    final clientTokensAvailable = tokenStore?.isAvailable ?? false;
    final unavailable = <String>[
      if (!odbcAvailable) 'odbc',
      if (!hubAuthAvailable) 'hub_auth',
      if (!clientTokensAvailable) 'client_tokens',
    ];

    return <String, Object?>{
      'odbc_available': odbcAvailable,
      'hub_auth_available': hubAuthAvailable,
      'client_tokens_available': clientTokensAvailable,
      'degraded': unavailable.isNotEmpty,
      if (unavailable.isNotEmpty) 'unavailable': unavailable,
    };
  }
}
