import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/batch_secret_store_mixin.dart';
import 'package:plug_agente/infrastructure/stores/odbc_credential_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

class _FakeOdbcCredentialSecretStore with BatchOdbcCredentialSecretStoreMixin implements IOdbcCredentialSecretStore {
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

class _UnavailableOdbcCredentialSecretStore
    with BatchOdbcCredentialSecretStoreMixin
    implements IOdbcCredentialSecretStore {
  @override
  bool get isAvailable => false;

  @override
  Future<void> deleteSecrets(String configId) async {}

  @override
  Future<OdbcCredentialSecrets> readSecrets(String configId) async => const OdbcCredentialSecrets();

  @override
  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets) async {}
}

Future<void> _insertConfig({
  required AppDatabase database,
  required String id,
  String connectionString = '',
}) async {
  final now = DateTime.utc(2025);
  await database
      .into(database.configTable)
      .insert(
        ConfigTableCompanion.insert(
          id: id,
          serverUrl: const Value('https://hub.example.com'),
          agentId: const Value('agent-1'),
          driverName: 'SQL Server',
          odbcDriverName: const Value('ODBC Driver 17 for SQL Server'),
          connectionString: connectionString,
          username: 'sa',
          databaseName: 'legacy_db',
          host: 'localhost',
          port: 1433,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OdbcCredentialStore', () {
    test('v30 migration migrates straggler password into secure storage on open', () async {
      final tempDir = await Directory.systemTemp.createTemp('odbc_v30_migration_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = '${tempDir.path}\\agent_config.db';
      final seedDb = AppDatabase(databaseFilePath: dbPath);
      await _insertConfig(
        database: seedDb,
        id: 'legacy-v30',
        connectionString: 'DSN=Legacy',
      );
      await seedDb.close();

      final sqliteDb = sqlite3.sqlite3.open(dbPath);
      try {
        sqliteDb
          ..execute('ALTER TABLE config_table ADD COLUMN password TEXT')
          ..execute(
            "UPDATE config_table SET password = 'v30-migrate-secret' WHERE id = 'legacy-v30'",
          )
          ..execute('PRAGMA user_version = 29');
      } finally {
        sqliteDb.dispose();
      }

      final secretStore = _FakeOdbcCredentialSecretStore();
      migrationOdbcCredentialSecretStoreFactory = () => secretStore;

      final database = AppDatabase(databaseFilePath: dbPath);
      addTearDown(() async {
        migrationOdbcCredentialSecretStoreFactory = null;
        await database.close();
      });
      final store = OdbcCredentialStore(
        database,
        credentialSecretStore: secretStore,
      );

      final result = await store.readCredentials('legacy-v30');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().password, 'v30-migrate-secret');
      expect(
        (await secretStore.readSecrets('legacy-v30')).password,
        'v30-migrate-secret',
      );

      final columns = await database.customSelect('PRAGMA table_info("config_table")').get();
      final columnNames = {for (final row in columns) row.read<String>('name')};
      expect(columnNames, isNot(contains('password')));
    });

    test('lazy migrates password embedded in connection string', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final secretStore = _FakeOdbcCredentialSecretStore();
      final store = OdbcCredentialStore(
        database,
        credentialSecretStore: secretStore,
      );

      await _insertConfig(
        database: database,
        id: 'cfg-legacy-cs',
        connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa;PWD=cs-secret',
      );

      final result = await store.readCredentials('cfg-legacy-cs');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().password, 'cs-secret');

      final row = await (database.select(
        database.configTable,
      )..where((tbl) => tbl.id.equals('cfg-legacy-cs'))).getSingle();
      expect(row.connectionString, isNot(contains('PWD=')));
      expect(row.connectionString, contains('SERVER=localhost'));
    });

    test('secure storage wins over legacy drift values', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final secretStore = _FakeOdbcCredentialSecretStore();
      final store = OdbcCredentialStore(
        database,
        credentialSecretStore: secretStore,
      );

      await _insertConfig(
        database: database,
        id: 'cfg-merge',
        connectionString: 'DRIVER={x};PWD=legacy-secret',
      );
      await secretStore.saveSecrets(
        'cfg-merge',
        const OdbcCredentialSecrets(password: 'secure-secret'),
      );

      final result = await store.readCredentials('cfg-merge');

      expect(result.getOrThrow().password, 'secure-secret');
    });

    test('keeps embedded password in drift when secure storage is unavailable', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final store = OdbcCredentialStore(
        database,
        credentialSecretStore: _UnavailableOdbcCredentialSecretStore(),
      );

      await _insertConfig(
        database: database,
        id: 'cfg-noop',
        connectionString: 'DRIVER={x};PWD=legacy-secret',
      );

      final result = await store.readCredentials('cfg-noop');

      expect(result.getOrThrow().password, 'legacy-secret');

      final row = await (database.select(database.configTable)..where((tbl) => tbl.id.equals('cfg-noop'))).getSingle();
      expect(row.connectionString, contains('PWD=legacy-secret'));
    });

    test('deleteAllSecrets clears secure storage and legacy drift columns', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final secretStore = _FakeOdbcCredentialSecretStore();
      final store = OdbcCredentialStore(
        database,
        credentialSecretStore: secretStore,
      );

      await _insertConfig(
        database: database,
        id: 'cfg-delete',
        connectionString: 'DRIVER={x};PWD=legacy-secret',
      );
      await secretStore.saveSecrets(
        'cfg-delete',
        const OdbcCredentialSecrets(password: 'secure-secret'),
      );

      final deleteResult = await store.deleteAllSecrets('cfg-delete');

      expect(deleteResult.isSuccess(), isTrue);
      expect((await secretStore.readSecrets('cfg-delete')).hasAny, isFalse);

      final row = await (database.select(
        database.configTable,
      )..where((tbl) => tbl.id.equals('cfg-delete'))).getSingle();
      expect(row.connectionString, isNot(contains('PWD=')));
    });
  });
}
