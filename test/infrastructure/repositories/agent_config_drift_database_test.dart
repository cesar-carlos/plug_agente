import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/batch_secret_store_mixin.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppDatabase (AgentConfigDataSource)', () {
    test('getAllConfigs returns empty list for fresh database', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db.getAllConfigs();
      expect(rows, isEmpty);
    });

    test('fresh database creates agent action tables', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final definitions = await db.select(db.agentActionDefinitionTable).get();
      final triggers = await db.select(db.agentActionTriggerTable).get();
      final executions = await db.select(db.agentActionExecutionTable).get();

      expect(definitions, isEmpty);
      expect(triggers, isEmpty);
      expect(executions, isEmpty);
    });

    test('fresh database creates rpc idempotency cache table', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db.select(db.rpcIdempotencyCacheTable).get();
      expect(rows, isEmpty);
    });

    test('saveConfig getConfigById getCurrentConfig deleteConfig round-trip', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final older = DateTime.utc(2024);
      final newer = DateTime.utc(2024, 6, 15);

      await db.saveConfig(
        ConfigTableCompanion.insert(
          id: 'cfg-old',
          driverName: 'SQL Server',
          connectionString: 'DSN=Old',
          username: 'sa',
          databaseName: 'db1',
          host: 'localhost',
          port: 1433,
          createdAt: older,
          updatedAt: older,
        ),
      );

      await db.saveConfig(
        ConfigTableCompanion.insert(
          id: 'cfg-new',
          driverName: 'SQL Anywhere',
          connectionString: 'DSN=New',
          username: 'dba',
          databaseName: 'db2',
          host: '127.0.0.1',
          port: 2638,
          createdAt: older,
          updatedAt: newer,
        ),
      );

      final all = await db.getAllConfigs();
      expect(all.length, 2);

      final byId = await db.getConfigById('cfg-new');
      expect(byId, isNotNull);
      expect(byId!.connectionString, 'DSN=New');

      final current = await db.getCurrentConfig();
      expect(current?.id, 'cfg-new');

      await db.deleteConfig('cfg-old');
      expect(await db.getConfigById('cfg-old'), isNull);
      expect((await db.getAllConfigs()).length, 1);
    });

    test('saveConfig updates row on conflict', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final t1 = DateTime.utc(2025);
      await db.saveConfig(
        ConfigTableCompanion.insert(
          id: 'single',
          driverName: 'SQL Server',
          connectionString: 'DSN=Before',
          username: 'u',
          databaseName: 'd',
          host: 'h',
          port: 1,
          createdAt: t1,
          updatedAt: t1,
        ),
      );

      final t2 = DateTime.utc(2025, 2);
      final existing = await db.getConfigById('single');
      expect(existing, isNotNull);
      await db.saveConfig(
        existing!.copyWith(
          connectionString: 'DSN=After',
          updatedAt: t2,
        ),
      );

      final row = await db.getConfigById('single');
      expect(row?.connectionString, 'DSN=After');
      expect(row?.updatedAt.toUtc(), t2);
    });

    test('opens when name column already exists before migration v12', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_db_migration_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = '${tempDir.path}\\agent_config.db';

      final initialDb = AppDatabase(databaseFilePath: dbPath);
      await initialDb.getAllConfigs();
      await initialDb.customStatement('PRAGMA user_version = 11;');
      await initialDb.close();

      final reopenedDb = AppDatabase(databaseFilePath: dbPath);
      addTearDown(reopenedDb.close);

      final rows = await reopenedDb.getAllConfigs();
      expect(rows, isEmpty);
    });

    test('migration v17 adds agent action process identity columns', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_db_migration_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = '${tempDir.path}\\agent_config.db';
      _createLegacyV16Database(dbPath);

      final db = AppDatabase(databaseFilePath: dbPath);
      addTearDown(db.close);

      await db.select(db.agentActionExecutionTable).get();
      final columns = await _readTableColumns(db, 'agent_action_execution_table');

      expect(columns, contains('process_executable'));
      expect(columns, contains('process_argument_count'));
      expect(columns, contains('process_command_preview'));
    });

    test('migration v30 drops legacy ODBC password column and migrates stragglers', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_db_migration_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = '${tempDir.path}\\agent_config.db';
      await _seedLegacyV29DatabaseWithPassword(
        dbPath,
        configId: 'legacy-odbc',
        password: 'legacy-v29-secret',
        connectionString: 'DSN=Legacy',
      );

      final secretStore = _FakeMigrationOdbcCredentialSecretStore();
      migrationOdbcCredentialSecretStoreFactory = () => secretStore;

      final db = AppDatabase(databaseFilePath: dbPath);
      addTearDown(() async {
        migrationOdbcCredentialSecretStoreFactory = null;
        await db.close();
      });

      expect(await _readUserVersion(db), 30);

      final columns = await _readTableColumns(db, 'config_table');
      expect(columns, isNot(contains('password')));

      final config = await db.getConfigById('legacy-odbc');
      expect(config, isNotNull);
      expect(config!.connectionString, 'DSN=Legacy');

      final storedSecrets = await secretStore.readSecrets('legacy-odbc');
      expect(storedSecrets.password, 'legacy-v29-secret');
    });

    test('migration v28 cleans orphan rows and adds foreign keys', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_db_migration_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = '${tempDir.path}\\agent_config.db';
      _createLegacyV27Database(dbPath);

      final db = AppDatabase(databaseFilePath: dbPath);
      addTearDown(db.close);

      final triggers = await db.select(db.agentActionTriggerTable).get();
      final chunks = await db.select(db.agentActionCapturedOutputChunkTable).get();

      expect(triggers.map((row) => row.id), ['trigger-valid']);
      expect(chunks.map((row) => row.executionId), ['exec-valid']);

      final triggerForeignKeys = await db.customSelect(
        'PRAGMA foreign_key_list(agent_action_trigger_table)',
      ).get();
      final chunkForeignKeys = await db.customSelect(
        'PRAGMA foreign_key_list(agent_action_captured_output_chunk_table)',
      ).get();

      expect(
        triggerForeignKeys.map((row) => row.read<String>('table')),
        contains('agent_action_definition_table'),
      );
      expect(
        chunkForeignKeys.map((row) => row.read<String>('table')),
        contains('agent_action_execution_table'),
      );
    });

    test('migration v18 adds agent action failure phase column', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_db_migration_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = '${tempDir.path}\\agent_config.db';
      _createLegacyV17Database(dbPath);

      final db = AppDatabase(databaseFilePath: dbPath);
      addTearDown(db.close);

      await db.select(db.agentActionExecutionTable).get();
      final columns = await _readTableColumns(db, 'agent_action_execution_table');

      expect(columns, contains('failure_phase'));
    });
  });
}

void _createLegacyV27Database(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    final now = DateTime.utc(2026, 5).millisecondsSinceEpoch;
    db
      ..execute('''
        CREATE TABLE config_table (
          id TEXT NOT NULL PRIMARY KEY,
          driver_name TEXT NOT NULL,
          connection_string TEXT NOT NULL,
          username TEXT NOT NULL,
          database_name TEXT NOT NULL,
          host TEXT NOT NULL,
          port INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE client_token_cache_table (
          id TEXT NOT NULL PRIMARY KEY,
          client_id TEXT NOT NULL,
          is_revoked INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          token_hash TEXT NOT NULL DEFAULT ''
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_definition_table (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          state TEXT NOT NULL,
          config_json TEXT NOT NULL,
          policies_json TEXT NOT NULL,
          definition_version INTEGER NOT NULL DEFAULT 1,
          definition_snapshot_hash TEXT NOT NULL DEFAULT '',
          last_preflight_snapshot_hash TEXT,
          last_preflight_validated_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_trigger_table (
          id TEXT NOT NULL PRIMARY KEY,
          action_id TEXT NOT NULL,
          type TEXT NOT NULL,
          name TEXT,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          schedule_json TEXT NOT NULL,
          last_scheduled_at INTEGER,
          last_run_at INTEGER,
          next_run_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_execution_table (
          id TEXT NOT NULL PRIMARY KEY,
          action_id TEXT NOT NULL,
          action_type TEXT NOT NULL,
          status TEXT NOT NULL,
          requested_at INTEGER NOT NULL,
          source TEXT NOT NULL,
          idempotency_key TEXT,
          requested_by TEXT,
          trace_id TEXT,
          runtime_instance_id TEXT,
          runtime_session_id TEXT,
          trigger_id TEXT,
          trigger_type TEXT,
          scheduled_at INTEGER,
          triggered_at INTEGER,
          queue_started_at INTEGER,
          process_started_at INTEGER,
          finished_at INTEGER,
          timeout_at INTEGER,
          pid INTEGER,
          exit_code INTEGER,
          process_executable TEXT,
          process_argument_count INTEGER,
          process_command_preview TEXT,
          stdout_text TEXT,
          stderr_text TEXT,
          stdout_truncated INTEGER NOT NULL DEFAULT 0,
          stderr_truncated INTEGER NOT NULL DEFAULT 0,
          stdout_stored_in_chunks INTEGER NOT NULL DEFAULT 0,
          stderr_stored_in_chunks INTEGER NOT NULL DEFAULT 0,
          definition_snapshot_hash TEXT,
          context_hash TEXT,
          redaction_applied INTEGER NOT NULL DEFAULT 0,
          failure_code TEXT,
          failure_phase TEXT,
          failure_message TEXT
        )
      ''')
      ..execute('''
        CREATE TABLE rpc_idempotency_cache_table (
          cache_key TEXT NOT NULL PRIMARY KEY,
          response_json TEXT NOT NULL,
          request_fingerprint TEXT,
          expires_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_remote_audit_table (
          id TEXT NOT NULL PRIMARY KEY,
          occurred_at INTEGER NOT NULL,
          rpc_method TEXT NOT NULL,
          action_id TEXT,
          execution_id TEXT,
          trace_id TEXT,
          requested_by TEXT,
          outcome TEXT NOT NULL,
          reason_code TEXT,
          rpc_error_code INTEGER,
          credential_present INTEGER NOT NULL DEFAULT 0,
          client_id TEXT,
          token_jti TEXT,
          runtime_instance_id TEXT,
          runtime_session_id TEXT,
          idempotency_key TEXT
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_captured_output_chunk_table (
          execution_id TEXT NOT NULL,
          stream TEXT NOT NULL,
          chunk_index INTEGER NOT NULL,
          utf8_offset INTEGER NOT NULL,
          payload TEXT NOT NULL,
          PRIMARY KEY (execution_id, stream, chunk_index)
        )
      ''')
      ..execute(
        'INSERT INTO agent_action_definition_table (id, name, type, state, config_json, policies_json, created_at, updated_at) '
        "VALUES ('action-valid', 'Valid', 'commandLine', 'active', '{}', '{}', $now, $now)",
      )
      ..execute(
        'INSERT INTO agent_action_trigger_table (id, action_id, type, schedule_json, created_at, updated_at) '
        "VALUES ('trigger-valid', 'action-valid', 'daily', '{}', $now, $now)",
      )
      ..execute(
        'INSERT INTO agent_action_trigger_table (id, action_id, type, schedule_json, created_at, updated_at) '
        "VALUES ('trigger-orphan', 'missing-action', 'daily', '{}', $now, $now)",
      )
      ..execute(
        'INSERT INTO agent_action_execution_table (id, action_id, action_type, status, requested_at, source) '
        "VALUES ('exec-valid', 'action-valid', 'commandLine', 'succeeded', $now, 'localUi')",
      )
      ..execute(
        'INSERT INTO agent_action_captured_output_chunk_table (execution_id, stream, chunk_index, utf8_offset, payload) '
        "VALUES ('exec-valid', 'stdout', 0, 0, 'ok')",
      )
      ..execute(
        'INSERT INTO agent_action_captured_output_chunk_table (execution_id, stream, chunk_index, utf8_offset, payload) '
        "VALUES ('exec-orphan', 'stdout', 0, 0, 'orphan')",
      )
      ..execute('PRAGMA user_version = 27');
  } finally {
    db.dispose();
  }
}

void _createLegacyV16Database(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db
      ..execute('''
        CREATE TABLE config_table (
          id TEXT NOT NULL PRIMARY KEY,
          driver_name TEXT NOT NULL,
          connection_string TEXT NOT NULL,
          username TEXT NOT NULL,
          database_name TEXT NOT NULL,
          host TEXT NOT NULL,
          port INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE client_token_cache_table (
          id TEXT NOT NULL PRIMARY KEY,
          client_id TEXT NOT NULL,
          is_revoked INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          token_hash TEXT NOT NULL DEFAULT ''
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_definition_table (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          state TEXT NOT NULL,
          config_json TEXT NOT NULL,
          policies_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_trigger_table (
          id TEXT NOT NULL PRIMARY KEY,
          action_id TEXT NOT NULL,
          type TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          schedule_json TEXT NOT NULL,
          next_run_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_execution_table (
          id TEXT NOT NULL PRIMARY KEY,
          action_id TEXT NOT NULL,
          action_type TEXT NOT NULL,
          status TEXT NOT NULL,
          requested_at INTEGER NOT NULL,
          source TEXT NOT NULL,
          idempotency_key TEXT,
          requested_by TEXT,
          trace_id TEXT,
          trigger_id TEXT,
          trigger_type TEXT,
          scheduled_at INTEGER,
          triggered_at INTEGER,
          queue_started_at INTEGER,
          process_started_at INTEGER,
          finished_at INTEGER,
          timeout_at INTEGER,
          pid INTEGER,
          exit_code INTEGER,
          stdout_text TEXT,
          stderr_text TEXT,
          stdout_truncated INTEGER NOT NULL DEFAULT 0,
          stderr_truncated INTEGER NOT NULL DEFAULT 0,
          definition_snapshot_hash TEXT,
          context_hash TEXT,
          redaction_applied INTEGER NOT NULL DEFAULT 0,
          failure_code TEXT,
          failure_message TEXT
        )
      ''')
      ..execute('PRAGMA user_version = 16');
  } finally {
    db.dispose();
  }
}

void _createLegacyV17Database(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db
      ..execute('''
        CREATE TABLE config_table (
          id TEXT NOT NULL PRIMARY KEY,
          driver_name TEXT NOT NULL,
          connection_string TEXT NOT NULL,
          username TEXT NOT NULL,
          database_name TEXT NOT NULL,
          host TEXT NOT NULL,
          port INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE client_token_cache_table (
          id TEXT NOT NULL PRIMARY KEY,
          client_id TEXT NOT NULL,
          is_revoked INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          token_hash TEXT NOT NULL DEFAULT ''
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_definition_table (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          state TEXT NOT NULL,
          config_json TEXT NOT NULL,
          policies_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_trigger_table (
          id TEXT NOT NULL PRIMARY KEY,
          action_id TEXT NOT NULL,
          type TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          schedule_json TEXT NOT NULL,
          next_run_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE agent_action_execution_table (
          id TEXT NOT NULL PRIMARY KEY,
          action_id TEXT NOT NULL,
          action_type TEXT NOT NULL,
          status TEXT NOT NULL,
          requested_at INTEGER NOT NULL,
          source TEXT NOT NULL,
          idempotency_key TEXT,
          requested_by TEXT,
          trace_id TEXT,
          trigger_id TEXT,
          trigger_type TEXT,
          scheduled_at INTEGER,
          triggered_at INTEGER,
          queue_started_at INTEGER,
          process_started_at INTEGER,
          finished_at INTEGER,
          timeout_at INTEGER,
          pid INTEGER,
          exit_code INTEGER,
          process_executable TEXT,
          process_argument_count INTEGER,
          process_command_preview TEXT,
          stdout_text TEXT,
          stderr_text TEXT,
          stdout_truncated INTEGER NOT NULL DEFAULT 0,
          stderr_truncated INTEGER NOT NULL DEFAULT 0,
          definition_snapshot_hash TEXT,
          context_hash TEXT,
          redaction_applied INTEGER NOT NULL DEFAULT 0,
          failure_code TEXT,
          failure_message TEXT
        )
      ''')
      ..execute('PRAGMA user_version = 17');
  } finally {
    db.dispose();
  }
}

Future<int> _readUserVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<Set<String>> _readTableColumns(AppDatabase db, String tableName) async {
  final rows = await db.customSelect('PRAGMA table_info("$tableName")').get();
  return {for (final row in rows) row.read<String>('name')};
}

class _FakeMigrationOdbcCredentialSecretStore
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

Future<void> _seedLegacyV29DatabaseWithPassword(
  String dbPath, {
  required String configId,
  required String password,
  required String connectionString,
}) async {
  final seedDb = AppDatabase(executor: NativeDatabase(File(dbPath)));
  await seedDb.getAllConfigs();
  await seedDb.close();

  final db = sqlite3.sqlite3.open(dbPath);
  try {
    final now = DateTime.utc(2025).millisecondsSinceEpoch;
    db
      ..execute('ALTER TABLE config_table ADD COLUMN password TEXT')
      ..execute(
        'INSERT INTO config_table ( '
        'id, server_url, agent_id, driver_name, odbc_driver_name, connection_string, '
        'username, password, database_name, host, port, created_at, updated_at '
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          configId,
          'https://hub.example.com',
          'agent-1',
          'SQL Server',
          'ODBC Driver 17 for SQL Server',
          connectionString,
          'sa',
          password,
          'legacy_db',
          'localhost',
          1433,
          now,
          now,
        ],
      )
      ..execute('PRAGMA user_version = 29');
  } finally {
    db.dispose();
  }
}
