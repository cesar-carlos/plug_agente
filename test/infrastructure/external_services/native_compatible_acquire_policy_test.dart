import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';

void main() {
  setUp(() {
    dotenv.clean();
  });

  group('NativeCompatibleAcquirePolicy pure classification', () {
    test('normalizeSql strips comments, collapses whitespace and trailing semicolons', () {
      expect(
        NativeCompatibleAcquirePolicy.normalizeSql('SELECT   id FROM t;;  '),
        'select id from t',
      );
    });

    test('isProbeQuery recognizes safe scalar probes', () {
      expect(NativeCompatibleAcquirePolicy.isProbeQuery('SELECT 1'), isTrue);
      expect(NativeCompatibleAcquirePolicy.isProbeQuery('select @@version as v'), isTrue);
      expect(NativeCompatibleAcquirePolicy.isProbeQuery('SELECT id FROM users'), isFalse);
    });

    test('isExplicitlyLimitedSelect accepts small explicit limits and rejects wildcards/large limits', () {
      expect(NativeCompatibleAcquirePolicy.isExplicitlyLimitedSelect('SELECT TOP 10 id FROM users'), isTrue);
      expect(NativeCompatibleAcquirePolicy.isExplicitlyLimitedSelect('SELECT id FROM users LIMIT 50'), isTrue);
      expect(NativeCompatibleAcquirePolicy.isExplicitlyLimitedSelect('SELECT TOP 10 * FROM users'), isFalse);
      expect(NativeCompatibleAcquirePolicy.isExplicitlyLimitedSelect('SELECT id FROM users LIMIT 500'), isFalse);
      expect(NativeCompatibleAcquirePolicy.isExplicitlyLimitedSelect('SELECT id FROM users'), isFalse);
    });

    test('isTransactionalDml accepts INSERT/UPDATE/DELETE/MERGE and rejects OUTPUT/RETURNING and selects', () {
      expect(NativeCompatibleAcquirePolicy.isTransactionalDml('INSERT INTO t (a) VALUES (1)'), isTrue);
      expect(NativeCompatibleAcquirePolicy.isTransactionalDml('UPDATE t SET a = 1'), isTrue);
      expect(NativeCompatibleAcquirePolicy.isTransactionalDml('DELETE FROM t WHERE a = 1 RETURNING a'), isFalse);
      expect(NativeCompatibleAcquirePolicy.isTransactionalDml('INSERT INTO t OUTPUT inserted.id VALUES (1)'), isFalse);
      expect(NativeCompatibleAcquirePolicy.isTransactionalDml('SELECT 1'), isFalse);
    });
  });

  group('NativeCompatibleAcquirePolicy.shouldUseAcquire', () {
    test('returns false when adaptive pooling is disabled', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: false));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sqlServer,
          request: _request('SELECT 1'),
          preparedExecution: _prepared('SELECT 1'),
          acquireOptions: null,
          timeout: null,
        ),
        isFalse,
      );
    });

    test('returns true for a probe query on SQL Server when enabled', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sqlServer,
          request: _request('SELECT 1'),
          preparedExecution: _prepared('SELECT 1'),
          acquireOptions: null,
          timeout: null,
        ),
        isTrue,
      );
    });

    test('returns false for SQL Anywhere even with a safe shape', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sybaseAnywhere,
          request: _request('SELECT 1'),
          preparedExecution: _prepared('SELECT 1'),
          acquireOptions: null,
          timeout: null,
        ),
        isFalse,
      );
    });

    test('returns false when a custom timeout is provided', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sqlServer,
          request: _request('SELECT 1'),
          preparedExecution: _prepared('SELECT 1'),
          acquireOptions: null,
          timeout: const Duration(seconds: 5),
          defaultQueryTimeout: const Duration(seconds: 60),
          connectionString: 'Driver={ODBC Driver};Server=localhost;',
        ),
        isFalse,
      );
    });

    test('returns true when timeout matches configured default', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sqlServer,
          request: _request('SELECT 1'),
          preparedExecution: _prepared('SELECT 1'),
          acquireOptions: null,
          timeout: const Duration(seconds: 60),
          defaultQueryTimeout: const Duration(seconds: 60),
          connectionString: 'Driver={ODBC Driver};Server=localhost;',
        ),
        isTrue,
      );
    });

    test('returns true for COUNT aggregate queries', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.postgresql,
          request: _request('SELECT COUNT(*) FROM users'),
          preparedExecution: _prepared('SELECT COUNT(*) FROM users'),
          acquireOptions: null,
          timeout: null,
        ),
        isTrue,
      );
    });

    test('returns false for unsafe result shapes', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sqlServer,
          request: _request('SELECT * FROM users'),
          preparedExecution: _prepared('SELECT * FROM users'),
          acquireOptions: null,
          timeout: null,
        ),
        isFalse,
      );
    });

    test('returns true when paginated (safe shape) on PostgreSQL', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.postgresql,
          request: _request(
            'SELECT id FROM users',
            pagination: const QueryPaginationRequest(page: 1, pageSize: 10),
          ),
          preparedExecution: _prepared('SELECT id FROM users'),
          acquireOptions: null,
          timeout: null,
        ),
        isTrue,
      );
    });

    test('honors the env-driven allowlist for exact normalized SQL', () async {
      dotenv.loadFromString(envString: 'ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST=select id from users');
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseAcquire(
          databaseType: DatabaseType.sqlServer,
          request: _request('SELECT id FROM users'),
          preparedExecution: _prepared('SELECT id FROM users'),
          acquireOptions: null,
          timeout: null,
        ),
        isTrue,
      );
    });
  });

  group('NativeCompatibleAcquirePolicy.shouldUseReadOnlyBatchParallel', () {
    test('returns false by default when env gate is off', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: null,
        ),
        isFalse,
      );
    });

    test('returns true for homogeneous SELECT batch on SQL Server when gate is on', () async {
      dotenv.loadFromString(envString: 'ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED=true');
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: null,
          connectionString: 'Driver={ODBC Driver};Server=localhost;',
        ),
        isTrue,
      );
    });

    test('returns false for SQL Anywhere and parameterized commands', () async {
      dotenv.loadFromString(envString: 'ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED=true');
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.sybaseAnywhere,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: null,
        ),
        isFalse,
      );
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'SELECT 1 WHERE id = @id', params: {'id': 1}),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: null,
        ),
        isFalse,
      );
    });

    test('returns false for non-default timeout until remembered compatible', () async {
      dotenv.loadFromString(envString: 'ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED=true');
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: const Duration(seconds: 5),
          connectionString: connectionString,
        ),
        isFalse,
      );
      policy.rememberNativeCompatibleTimeout(
        connectionString: connectionString,
        timeout: const Duration(seconds: 5),
      );
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: const Duration(seconds: 5),
          connectionString: connectionString,
        ),
        isTrue,
      );
    });

    test('returns true when timeout matches configured default', () async {
      dotenv.loadFromString(envString: 'ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED=true');
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseReadOnlyBatchParallel(
          databaseType: DatabaseType.postgresql,
          commands: const [
            SqlCommand(sql: 'SELECT 1'),
            SqlCommand(sql: 'SELECT 2'),
          ],
          timeout: ConnectionConstants.defaultQueryTimeout,
          connectionString: 'Driver={PostgreSQL};Server=localhost;',
        ),
        isTrue,
      );
    });
  });

  group('NativeCompatibleAcquirePolicy.shouldUseTransactionalBatch', () {
    test('returns true for all-DML batch on SQL Server when enabled', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseTransactionalBatch(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'INSERT INTO t (a) VALUES (1)'),
            SqlCommand(sql: 'UPDATE t SET a = 2'),
          ],
        ),
        isTrue,
      );
    });

    test('returns false when any command is not native-compatible DML', () async {
      final policy = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        policy.shouldUseTransactionalBatch(
          databaseType: DatabaseType.sqlServer,
          commands: const [
            SqlCommand(sql: 'INSERT INTO t (a) VALUES (1)'),
            SqlCommand(sql: 'SELECT 1'),
          ],
        ),
        isFalse,
      );
    });

    test('returns false for empty commands and when disabled', () async {
      final enabled = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: true));
      expect(
        enabled.shouldUseTransactionalBatch(
          databaseType: DatabaseType.sqlServer,
          commands: const [],
        ),
        isFalse,
      );

      final disabled = NativeCompatibleAcquirePolicy(featureFlags: await _flags(enabled: false));
      expect(
        disabled.shouldUseTransactionalBatch(
          databaseType: DatabaseType.sqlServer,
          commands: const [SqlCommand(sql: 'INSERT INTO t (a) VALUES (1)')],
        ),
        isFalse,
      );
    });
  });
}

Future<FeatureFlags> _flags({required bool enabled}) async {
  final flags = FeatureFlags(InMemoryAppSettingsStore());
  await flags.setEnableOdbcExperimentalDriverAdaptivePooling(enabled);
  return flags;
}

QueryRequest _request(String sql, {QueryPaginationRequest? pagination}) {
  return QueryRequest(
    id: 'req-test',
    agentId: 'agent-test',
    query: sql,
    timestamp: DateTime(2024, 2, 3),
    pagination: pagination,
  );
}

OdbcPreparedQueryExecution _prepared(String sql) {
  return OdbcPreparedQueryExecution(sql: sql, parameters: null);
}
