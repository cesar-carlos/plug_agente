import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';

mixin BatchHubAuthSecretStoreMixin implements IHubAuthSecretStore {
  @override
  Future<Map<String, HubAuthSecrets>> readSecretsForConfigIds(
    Iterable<String> configIds,
  ) async {
    final ids = configIds.toList(growable: false);
    if (ids.isEmpty) {
      return const <String, HubAuthSecrets>{};
    }

    final entries = await Future.wait(
      ids.map((configId) async {
        return MapEntry(configId, await readSecrets(configId));
      }),
    );
    return Map<String, HubAuthSecrets>.fromEntries(entries);
  }
}

mixin BatchOdbcCredentialSecretStoreMixin implements IOdbcCredentialSecretStore {
  @override
  Future<Map<String, OdbcCredentialSecrets>> readSecretsForConfigIds(
    Iterable<String> configIds,
  ) async {
    final ids = configIds.toList(growable: false);
    if (ids.isEmpty) {
      return const <String, OdbcCredentialSecrets>{};
    }

    final entries = await Future.wait(
      ids.map((configId) async {
        return MapEntry(configId, await readSecrets(configId));
      }),
    );
    return Map<String, OdbcCredentialSecrets>.fromEntries(entries);
  }
}
