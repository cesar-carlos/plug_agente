import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/stores/batch_secret_store_mixin.dart';
import 'package:plug_agente/infrastructure/stores/hub_session_store.dart';
import 'package:plug_agente/infrastructure/stores/odbc_credential_store.dart';

class _FakeHubAuthSecretStore
    with BatchHubAuthSecretStoreMixin
    implements IHubAuthSecretStore {
  final Map<String, HubAuthSecrets> _storage = <String, HubAuthSecrets>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecrets(String configId) async {
    _storage.remove(configId);
  }

  @override
  Future<HubAuthSecrets> readSecrets(String configId) async {
    return _storage[configId] ?? const HubAuthSecrets();
  }

  @override
  Future<void> saveSecrets(String configId, HubAuthSecrets secrets) async {
    _storage[configId] = secrets;
  }
}

class _FakeOdbcCredentialSecretStore
    with BatchOdbcCredentialSecretStoreMixin
    implements IOdbcCredentialSecretStore {
  final Map<String, OdbcCredentialSecrets> _storage = <String, OdbcCredentialSecrets>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecrets(String configId) async {
    _storage.remove(configId);
  }

  @override
  Future<OdbcCredentialSecrets> readSecrets(String configId) async {
    return _storage[configId] ?? const OdbcCredentialSecrets();
  }

  @override
  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets) async {
    _storage[configId] = secrets;
  }
}

class _CountingHubAuthSecretStore
    with BatchHubAuthSecretStoreMixin
    implements IHubAuthSecretStore {
  final Map<String, HubAuthSecrets> _storage = <String, HubAuthSecrets>{};
  int batchReadCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecrets(String configId) async {
    _storage.remove(configId);
  }

  @override
  Future<HubAuthSecrets> readSecrets(String configId) async {
    return _storage[configId] ?? const HubAuthSecrets();
  }

  @override
  Future<Map<String, HubAuthSecrets>> readSecretsForConfigIds(
    Iterable<String> configIds,
  ) async {
    batchReadCount++;
    return super.readSecretsForConfigIds(configIds);
  }

  @override
  Future<void> saveSecrets(String configId, HubAuthSecrets secrets) async {
    _storage[configId] = secrets;
  }
}

class _CountingOdbcCredentialSecretStore
    with BatchOdbcCredentialSecretStoreMixin
    implements IOdbcCredentialSecretStore {
  final Map<String, OdbcCredentialSecrets> _storage = <String, OdbcCredentialSecrets>{};
  int batchReadCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecrets(String configId) async {
    _storage.remove(configId);
  }

  @override
  Future<OdbcCredentialSecrets> readSecrets(String configId) async {
    return _storage[configId] ?? const OdbcCredentialSecrets();
  }

  @override
  Future<Map<String, OdbcCredentialSecrets>> readSecretsForConfigIds(
    Iterable<String> configIds,
  ) async {
    batchReadCount++;
    return super.readSecretsForConfigIds(configIds);
  }

  @override
  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets) async {
    _storage[configId] = secrets;
  }
}

AgentConfigRepository _createRepository({
  required AppDatabase database,
  required IHubAuthSecretStore authSecretStore,
  required IOdbcCredentialSecretStore odbcSecretStore,
}) {
  return AgentConfigRepository(
    database,
    authSecretStore: authSecretStore,
    hubSessionStore: HubSessionStore(
      database,
      authSecretStore: authSecretStore,
    ),
    odbcCredentialSecretStore: odbcSecretStore,
    odbcCredentialStore: OdbcCredentialStore(
      database,
      credentialSecretStore: odbcSecretStore,
    ),
  );
}

void main() {
  group('AgentConfigRepository legacy compatibility', () {
    test('should load legacy-like row with profile defaults', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);

      final nowEpochMs = DateTime.utc(2025).millisecondsSinceEpoch;
      await database.customStatement(
        '''
        INSERT INTO config_table (
          id,
          server_url,
          agent_id,
          driver_name,
          odbc_driver_name,
          connection_string,
          username,
          database_name,
          host,
          port,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'legacy-config',
          'https://legacy.example.com',
          'legacy-agent',
          'SQL Server',
          'ODBC Driver 17 for SQL Server',
          'DRIVER={x};PWD=secret',
          'sa',
          'legacy_db',
          'localhost',
          1433,
          nowEpochMs,
          nowEpochMs,
        ],
      );

      final authSecretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();
      final repository = _createRepository(
        database: database,
        authSecretStore: authSecretStore,
        odbcSecretStore: odbcSecretStore,
      );
      final result = await repository.getCurrentConfig();

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow();
      expect(config.id, equals('legacy-config'));
      expect(config.password, 'secret');
      expect(config.nome, isEmpty);
      expect(config.nomeFantasia, isEmpty);
      expect(config.cnaeCnpjCpf, isEmpty);
      expect(config.telefone, isEmpty);
      expect(config.email, isEmpty);
      expect(config.endereco, isEmpty);
      expect(config.cep, isEmpty);
      expect(config.observacao, isEmpty);
    });

    test('should migrate legacy auth secrets into secure storage on load', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final secretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();

      final nowEpochMs = DateTime.utc(2025).millisecondsSinceEpoch;
      await database.customStatement(
        '''
        INSERT INTO config_table (
          id,
          server_url,
          agent_id,
          auth_token,
          refresh_token,
          auth_username,
          auth_password,
          driver_name,
          odbc_driver_name,
          connection_string,
          username,
          database_name,
          host,
          port,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'legacy-secrets',
          'https://legacy.example.com',
          'legacy-agent',
          'access-token',
          'refresh-token',
          'agent_user',
          'agent_pass',
          'SQL Server',
          'ODBC Driver 17 for SQL Server',
          'DRIVER={x};PWD=secret',
          'sa',
          'legacy_db',
          'localhost',
          1433,
          nowEpochMs,
          nowEpochMs,
        ],
      );

      final repository = _createRepository(
        database: database,
        authSecretStore: secretStore,
        odbcSecretStore: odbcSecretStore,
      );

      final result = await repository.getCurrentConfig();

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow();
      expect(config.authToken, 'access-token');
      expect(config.refreshToken, 'refresh-token');
      expect(config.authPassword, 'agent_pass');
      expect(config.password, 'secret');

      final storedSecrets = await secretStore.readSecrets('legacy-secrets');
      expect(storedSecrets.authToken, 'access-token');
      expect(storedSecrets.refreshToken, 'refresh-token');
      expect(storedSecrets.authPassword, 'agent_pass');

      final storedOdbcSecrets = await odbcSecretStore.readSecrets('legacy-secrets');
      expect(storedOdbcSecrets.password, 'secret');
    });

    test('save should preserve current secure tokens when config has stale tokens', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final secretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();

      final now = DateTime.utc(2025);
      await database
          .into(database.configTable)
          .insert(
            ConfigTableCompanion.insert(
              id: 'cfg-secure',
              serverUrl: const Value('https://hub.example.com'),
              agentId: const Value('agent-1'),
              driverName: 'SQL Server',
              odbcDriverName: const Value('ODBC Driver 17 for SQL Server'),
              connectionString: '',
              username: '',
              databaseName: '',
              host: 'localhost',
              port: 1433,
              authUsername: const Value('agent_user'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await secretStore.saveSecrets(
        'cfg-secure',
        const HubAuthSecrets(
          authToken: 'fresh-access',
          refreshToken: 'fresh-refresh',
          authPassword: 'agent_pass',
        ),
      );
      await odbcSecretStore.saveSecrets(
        'cfg-secure',
        const OdbcCredentialSecrets(password: 'db-secret'),
      );

      final repository = _createRepository(
        database: database,
        authSecretStore: secretStore,
        odbcSecretStore: odbcSecretStore,
      );

      final loaded = (await repository.getById('cfg-secure')).getOrThrow();
      final staleConfig = loaded.copyWith(
        authToken: 'expired-access',
        refreshToken: 'expired-refresh',
        authPassword: 'new_agent_pass',
        password: '',
        nomeFantasia: 'Updated',
        updatedAt: now.add(const Duration(minutes: 1)),
      );

      final saveResult = await repository.save(staleConfig);

      expect(saveResult.isSuccess(), isTrue);
      final storedSecrets = await secretStore.readSecrets('cfg-secure');
      expect(storedSecrets.authToken, 'fresh-access');
      expect(storedSecrets.refreshToken, 'fresh-refresh');
      expect(storedSecrets.authPassword, 'new_agent_pass');

      final storedOdbcSecrets = await odbcSecretStore.readSecrets('cfg-secure');
      expect(storedOdbcSecrets.password, 'db-secret');

      final row = await repository.getByIdMetadata('cfg-secure');
      expect(row.getOrThrow().authToken, isNull);
      expect(row.getOrThrow().refreshToken, isNull);
      expect(row.getOrThrow().authPassword, isNull);
      expect(row.getOrThrow().password, isNull);
    });

    test('save should persist ODBC secrets securely and redact drift columns', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final authSecretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();
      final repository = _createRepository(
        database: database,
        authSecretStore: authSecretStore,
        odbcSecretStore: odbcSecretStore,
      );

      final now = DateTime.utc(2025);
      final config = ConfigTableCompanion.insert(
        id: 'cfg-odbc-save',
        serverUrl: const Value('https://hub.example.com'),
        agentId: const Value('agent-1'),
        driverName: 'SQL Server',
        odbcDriverName: const Value('ODBC Driver 17 for SQL Server'),
        connectionString:
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa;PWD=save-secret',
        username: 'sa',
        databaseName: 'demo',
        host: 'localhost',
        port: 1433,
        createdAt: now,
        updatedAt: now,
      );
      await database.into(database.configTable).insert(config);

      final loaded = (await repository.getById('cfg-odbc-save')).getOrThrow();
      final saveResult = await repository.save(
        loaded.copyWith(
          nomeFantasia: 'Updated',
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      );

      expect(saveResult.isSuccess(), isTrue);

      final storedOdbcSecrets = await odbcSecretStore.readSecrets('cfg-odbc-save');
      expect(storedOdbcSecrets.password, 'save-secret');

      final driftRow = await (database.select(database.configTable)
            ..where((tbl) => tbl.id.equals('cfg-odbc-save')))
          .getSingle();
      expect(driftRow.connectionString, isNot(contains('PWD=')));
      expect(driftRow.connectionString, contains('SERVER=localhost'));
    });

    test('getByIdMetadata should not leak ODBC password or embedded PWD', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final authSecretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();

      final nowEpochMs = DateTime.utc(2025).millisecondsSinceEpoch;
      await database.customStatement(
        '''
        INSERT INTO config_table (
          id,
          server_url,
          agent_id,
          driver_name,
          odbc_driver_name,
          connection_string,
          username,
          database_name,
          host,
          port,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'legacy-metadata',
          'https://legacy.example.com',
          'legacy-agent',
          'SQL Server',
          'ODBC Driver 17 for SQL Server',
          'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa;PWD=metadata-secret',
          'sa',
          'legacy_db',
          'localhost',
          1433,
          nowEpochMs,
          nowEpochMs,
        ],
      );

      final repository = _createRepository(
        database: database,
        authSecretStore: authSecretStore,
        odbcSecretStore: odbcSecretStore,
      );

      final metadata = (await repository.getByIdMetadata('legacy-metadata')).getOrThrow();

      expect(metadata.password, isNull);
      expect(metadata.connectionString, isNot(contains('PWD=')));
      expect(metadata.connectionString, contains('SERVER=localhost'));
    });

    test('resolveConnectionString should inject secure password after save and reload', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final authSecretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();
      final repository = _createRepository(
        database: database,
        authSecretStore: authSecretStore,
        odbcSecretStore: odbcSecretStore,
      );
      final configService = ConfigService(ConfigValidator());

      final now = DateTime.utc(2025);
      final initialConfig = Config(
        id: 'cfg-resolve',
        agentId: 'agent-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString: '',
        username: 'sa',
        password: 'runtime-secret',
        databaseName: 'demo',
        host: 'localhost',
        port: 1433,
        createdAt: now,
        updatedAt: now,
      );

      final saveResult = await repository.save(
        initialConfig.copyWith(
          connectionString: configService.generateConnectionStringForPersistence(initialConfig),
        ),
      );
      expect(saveResult.isSuccess(), isTrue);

      final metadata = (await repository.getByIdMetadata('cfg-resolve')).getOrThrow();
      expect(metadata.password, isNull);
      expect(metadata.connectionString, isNot(contains('PWD=')));

      final reloaded = (await repository.getById('cfg-resolve')).getOrThrow();
      expect(reloaded.password, 'runtime-secret');

      final resolved = reloaded.resolveConnectionString();
      expect(resolved, contains('PWD=runtime-secret'));
      expect(resolved, contains('SERVER=localhost,1433'));
    });

    test('getAll should batch-load secrets and migrate legacy rows', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final authSecretStore = _CountingHubAuthSecretStore();
      final odbcSecretStore = _CountingOdbcCredentialSecretStore();
      final repository = _createRepository(
        database: database,
        authSecretStore: authSecretStore,
        odbcSecretStore: odbcSecretStore,
      );

      final nowEpochMs = DateTime.utc(2025).millisecondsSinceEpoch;
      for (final configId in <String>['cfg-batch-a', 'cfg-batch-b']) {
        await database.customStatement(
          '''
          INSERT INTO config_table (
            id,
            server_url,
            agent_id,
            auth_token,
            refresh_token,
            auth_username,
            auth_password,
            driver_name,
            odbc_driver_name,
            connection_string,
            username,
            database_name,
            host,
            port,
            created_at,
            updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          <Object?>[
            configId,
            'https://legacy.example.com',
            'legacy-agent',
            '${configId}_access',
            '${configId}_refresh',
            '${configId}_user',
            '${configId}_hub_pass',
            'SQL Server',
            'ODBC Driver 17 for SQL Server',
            'DRIVER={x};PWD=${configId}_db_pass',
            'sa',
            'legacy_db',
            'localhost',
            1433,
            nowEpochMs,
            nowEpochMs,
          ],
        );
      }

      final result = await repository.getAll();

      expect(result.isSuccess(), isTrue);
      final configs = result.getOrThrow();
      expect(configs, hasLength(2));

      final configA = configs.firstWhere((config) => config.id == 'cfg-batch-a');
      final configB = configs.firstWhere((config) => config.id == 'cfg-batch-b');
      expect(configA.authToken, 'cfg-batch-a_access');
      expect(configA.refreshToken, 'cfg-batch-a_refresh');
      expect(configA.authPassword, 'cfg-batch-a_hub_pass');
      expect(configA.password, 'cfg-batch-a_db_pass');
      expect(configB.authToken, 'cfg-batch-b_access');
      expect(configB.refreshToken, 'cfg-batch-b_refresh');
      expect(configB.authPassword, 'cfg-batch-b_hub_pass');
      expect(configB.password, 'cfg-batch-b_db_pass');

      expect(authSecretStore.batchReadCount, 1);
      expect(odbcSecretStore.batchReadCount, 1);

      final migratedHubA = await authSecretStore.readSecrets('cfg-batch-a');
      final migratedHubB = await authSecretStore.readSecrets('cfg-batch-b');
      expect(migratedHubA.authToken, 'cfg-batch-a_access');
      expect(migratedHubB.authToken, 'cfg-batch-b_access');

      final migratedOdbcA = await odbcSecretStore.readSecrets('cfg-batch-a');
      final migratedOdbcB = await odbcSecretStore.readSecrets('cfg-batch-b');
      expect(migratedOdbcA.password, 'cfg-batch-a_db_pass');
      expect(migratedOdbcB.password, 'cfg-batch-b_db_pass');
    });

    test('delete should clear hub and ODBC secrets', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final authSecretStore = _FakeHubAuthSecretStore();
      final odbcSecretStore = _FakeOdbcCredentialSecretStore();
      final repository = _createRepository(
        database: database,
        authSecretStore: authSecretStore,
        odbcSecretStore: odbcSecretStore,
      );

      final now = DateTime.utc(2025);
      await database
          .into(database.configTable)
          .insert(
            ConfigTableCompanion.insert(
              id: 'cfg-delete',
              serverUrl: const Value('https://hub.example.com'),
              agentId: const Value('agent-1'),
              driverName: 'SQL Server',
              odbcDriverName: const Value('ODBC Driver 17 for SQL Server'),
              connectionString: 'DRIVER={x};PWD=delete-secret',
              username: 'sa',
              databaseName: 'demo',
              host: 'localhost',
              port: 1433,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await authSecretStore.saveSecrets(
        'cfg-delete',
        const HubAuthSecrets(authPassword: 'hub-secret'),
      );
      await odbcSecretStore.saveSecrets(
        'cfg-delete',
        const OdbcCredentialSecrets(password: 'delete-secret'),
      );

      final deleteResult = await repository.delete('cfg-delete');

      expect(deleteResult.isSuccess(), isTrue);
      expect((await authSecretStore.readSecrets('cfg-delete')).hasAny, isFalse);
      expect((await odbcSecretStore.readSecrets('cfg-delete')).hasAny, isFalse);
    });
  });
}
