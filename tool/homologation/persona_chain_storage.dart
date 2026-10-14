import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/odbc_connection_string_secrets.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_odbc_credential_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_token_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/hub_session_store.dart';
import 'package:plug_agente/infrastructure/stores/odbc_credential_store.dart';

/// Real Windows DPAPI backend; only the support-directory lookup is redirected.
/// No production directory, legacy migration or platform-channel vault is used.
void registerChainVault(Directory session) {
  if (!Platform.isWindows) throw StateError('Windows DPAPI fixture is required.');
  final vault = Directory('${session.path}/vault')..createSync();
  if (Directory(vault.resolveSymbolicLinksSync()).parent.path != session.resolveSymbolicLinksSync()) {
    throw StateError('Fixture vault must not be a symbolic link.');
  }
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      if (call.method != 'getApplicationSupportDirectory') {
        throw StateError('Only the private fixture support directory is available.');
      }
      return vault.path;
    },
  );
  FlutterSecureStorageWindows.registerWith();
}

class ChainAgentStorage {
  ChainAgentStorage(String session, this.engine)
    : _boot = File('$session/$engine-boot.json'),
      database = AppDatabase(executor: NativeDatabase(File('$session/$engine-config.sqlite'))) {
    const secure = FlutterSecureStorage();
    final hub = FlutterSecureHubAuthSecretStore(secureStorage: secure, keyPrefix: '${engine}_hub_');
    final odbc = FlutterSecureOdbcCredentialSecretStore(secureStorage: secure, keyPrefix: '${engine}_odbc_');
    configs = AgentConfigRepository(
      database,
      authSecretStore: hub,
      hubSessionStore: HubSessionStore(database, authSecretStore: hub),
      odbcCredentialSecretStore: odbc,
      odbcCredentialStore: OdbcCredentialStore(database, credentialSecretStore: odbc),
    );
    tokens = ClientTokenRepository(
      ClientTokenLocalDataSource(database),
      secretStore: FlutterSecureTokenSecretStore(secureStorage: secure, keyPrefix: '${engine}_token_'),
    );
  }

  final String engine;
  final File _boot;
  final AppDatabase database;
  late final AgentConfigRepository configs;
  late final ClientTokenRepository tokens;
  late String tokenId;
  late String tokenValue;
  bool get resumed => _boot.existsSync();

  Future<Config> open(Config initial, String clientId) async {
    final resume = resumed;
    if (resume) {
      final boot = jsonDecode(await _boot.readAsString()) as Map<String, dynamic>;
      final config = (await configs.getCurrentConfig()).getOrThrow();
      if (config.id != boot['configId'] ||
          config.agentId != initial.agentId ||
          config.databaseName != initial.databaseName ||
          config.serverUrl != initial.serverUrl) {
        throw StateError('Persistent fixture binding differs from the requested source.');
      }
      tokenId = boot['tokenId'] as String;
      tokenValue = (await tokens.getTokenSecret(tokenId)).getOrThrow().tokenValue ?? '';
    } else {
      if ((await configs.getAllMetadata()).getOrThrow().isNotEmpty) {
        throw StateError('Incomplete fixture bootstrap; refusing to replace persisted credentials.');
      }
      (await configs.save(initial)).getOrThrow();
      final created = (await tokens.createTokenWithIdentity(
        ClientTokenCreateRequest(
          clientId: clientId,
          agentId: initial.agentId,
          name: 'Isolated chain fixture',
          allTables: false,
          allViews: false,
          globalPermissions: const ClientPermissionSet(canRead: true, canUpdate: true, canDelete: true),
          rules: [
            for (final table in [
              'operation_fixture',
              'schema_parent',
              'schema_child',
              for (var index = 0; index < 15; index++) 'wide_${index.toString().padLeft(2, '0')}',
            ])
              for (final name in {
                table,
                switch (engine) {
                  'postgres' => 'public.$table',
                  'mssql' => 'dbo.$table',
                  'sybase' => 'dba.$table',
                  _ => table,
                },
              })
                ClientTokenRule(
                  resource: DatabaseResource(resourceType: DatabaseResourceType.table, name: name),
                  permissions: ClientPermissionSet(
                    canRead: true,
                    canUpdate: table == 'operation_fixture',
                    canDelete: table == 'operation_fixture',
                  ),
                  effect: ClientTokenRuleEffect.allow,
                ),
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.view,
                name: switch (engine) {
                  'postgres' => 'public.wide_15',
                  'mssql' => 'dbo.wide_15',
                  'sybase' => 'dba.wide_15',
                  _ => 'wide_15',
                },
              ),
              permissions: const ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
              effect: ClientTokenRuleEffect.allow,
            ),
          ],
          payload: {'database': initial.databaseName},
        ),
      )).getOrThrow();
      tokenId = created.tokenId;
      tokenValue = created.tokenValue;
    }
    final config = (await configs.getCurrentConfig()).getOrThrow();
    if (tokenValue.isEmpty || config.authToken == null || config.refreshToken == null || config.password == null) {
      throw StateError('Persistent fixture vault is incomplete; bootstrap fallback is prohibited.');
    }
    final row = await database.select(database.configTable).getSingle();
    final tokenRows = await database.select(database.clientTokenCacheTable).get();
    if (row.authToken != null ||
        row.refreshToken != null ||
        row.authPassword != null ||
        OdbcConnectionStringSecrets.extractPasswordFromConnectionString(row.connectionString) != null ||
        tokenRows.length != 1 ||
        tokenRows.single.tokenValue != '__secure_storage__') {
      throw StateError('Fixture SQLite must contain metadata only, never raw secrets.');
    }
    if (!resume) {
      final pending = File('${_boot.path}.tmp');
      await pending.writeAsString(jsonEncode({'configId': config.id, 'tokenId': tokenId}), flush: true);
      await pending.rename(_boot.path);
    }
    return config;
  }
}
