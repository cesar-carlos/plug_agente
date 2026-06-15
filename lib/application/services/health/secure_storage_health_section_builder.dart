import 'package:plug_agente/application/services/health/secure_storage_runtime_probe.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

final class SecureStorageHealthSectionBuilder {
  const SecureStorageHealthSectionBuilder({
    IOdbcCredentialSecretStore? odbcCredentialSecretStore,
    IHubAuthSecretStore? hubAuthSecretStore,
    ITokenSecretStore? tokenSecretStore,
    SecureStorageRuntimeProbe? runtimeProbe,
  }) : _odbcCredentialSecretStore = odbcCredentialSecretStore,
       _hubAuthSecretStore = hubAuthSecretStore,
       _tokenSecretStore = tokenSecretStore,
       _runtimeProbe = runtimeProbe;

  final IOdbcCredentialSecretStore? _odbcCredentialSecretStore;
  final IHubAuthSecretStore? _hubAuthSecretStore;
  final ITokenSecretStore? _tokenSecretStore;
  final SecureStorageRuntimeProbe? _runtimeProbe;

  Map<String, Object?>? build() {
    return _composeSection(runtimeProbeOk: _runtimeProbe?.lastProbeOk);
  }

  Future<Map<String, Object?>?> buildFresh() async {
    final runtimeProbe = _runtimeProbe;
    final runtimeProbeOk = runtimeProbe == null ? null : await runtimeProbe.probe();
    return _composeSection(runtimeProbeOk: runtimeProbeOk);
  }

  Map<String, Object?>? _composeSection({required bool? runtimeProbeOk}) {
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
      if (runtimeProbeOk == false) 'runtime_probe',
    ];

    final runtimeProbe = _runtimeProbe;
    return <String, Object?>{
      'odbc_available': odbcAvailable,
      'hub_auth_available': hubAuthAvailable,
      'client_tokens_available': clientTokensAvailable,
      'degraded': unavailable.isNotEmpty,
      if (unavailable.isNotEmpty) 'unavailable': unavailable,
      'runtime_probe_ok': ?runtimeProbeOk,
      if (runtimeProbe?.lastProbeAt != null) 'last_probe_at': runtimeProbe!.lastProbeAt!.toUtc().toIso8601String(),
      if (runtimeProbe?.lastProbeError != null) 'last_probe_error': runtimeProbe!.lastProbeError,
    };
  }
}
