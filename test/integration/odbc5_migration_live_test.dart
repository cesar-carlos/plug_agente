import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_multi_result_stream_collector.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

import '../helpers/e2e_env.dart';
import '../helpers/mock_odbc_connection_settings.dart';

/// Mandatory driver selection: one driver's success cannot stand in for another.
void main() async {
  await E2EEnv.load();
  for (final driver in ['SQL Anywhere', 'SQL Server']) {
    final dsn = driver == 'SQL Server' ? E2EEnv.get('ODBC_TEST_DSN_SQL_SERVER') : E2EEnv.get('ODBC_TEST_DSN');
    group('odbc_fast 5 migration / $driver', () {
      late odbc.ServiceLocator locator;
      late odbc.OdbcService service;
      late MockOdbcConnectionSettings settings;

      setUpAll(() async {
        if (dsn == null || dsn.isEmpty) return;
        settings = MockOdbcConnectionSettings(poolSize: 2);
        locator = createAsyncOdbcServiceLocatorForSettings(settings);
        service = locator.asyncService;
        _confirmedVoid(await service.initialize(), 'initialize');
      });
      tearDownAll(() {
        if (dsn != null && dsn.isNotEmpty) locator.shutdown();
      });

      test('connect, query and named streaming use the selected driver', () async {
        final connection = _confirmed(await service.connect(dsn!), 'connect');
        try {
          final result = _confirmed(await service.executeQuery('SELECT 1 AS v', connectionId: connection.id), 'query');
          expect(result.rows.single.single, 1);
          var rows = 0;
          await for (final batch in service.streamQueryNamed(
            connection.id,
            'SELECT CAST(:value AS INTEGER) AS v',
            {'value': 7},
            fetchSize: 1,
            chunkSize: 64 * 1024,
          )) {
            final result = _confirmed(batch, 'named_stream');
            rows += result.rows.length;
            expect(result.rows.single.single, 7);
          }
          expect(rows, 1);
          final text = _confirmed(
            await service.executeQueryNamed(connection.id, 'SELECT CAST(:value AS NVARCHAR(128)) AS v', {
              'value': 'ação 漢字',
            }),
            'unicode_parameter',
          );
          expect(text.rows.single.single, 'ação 漢字');
        } finally {
          _confirmedVoid(await service.disconnect(connection.id), 'disconnect');
        }
      }, tags: ['live']);

      for (final nativePool in [false, true]) {
        test('20 acquire/execute/release cycles (${nativePool ? 'native' : 'lease'})', () async {
          final pool = nativePool
              ? OdbcNativeConnectionPool(service, settings) as IConnectionPool
              : OdbcConnectionPool(service, settings);
          try {
            for (var i = 0; i < 20; i++) {
              final id = _confirmed(await pool.acquire(dsn!), 'pool_acquire');
              try {
                final result = _confirmed(await service.executeQuery('SELECT 1 AS v', connectionId: id), 'pool_query');
                expect(result.rows.single.single, 1);
              } finally {
                _confirmedVoid(await pool.release(id), 'pool_release');
              }
              expect(_confirmed(await pool.getActiveCount(), 'pool_count'), 0);
            }
          } finally {
            _confirmedVoid(await pool.closeAll(), 'pool_close');
          }
        }, tags: ['live']);
      }

      test('20 gateway named streaming cycles with a slow consumer', () async {
        final gateway = OdbcStreamingGateway(service, settings);
        for (var i = 0; i < 20; i++) {
          var rows = 0;
          final result = await gateway.executeQueryStream(
            'SELECT CAST(:value AS INTEGER) AS v',
            dsn!,
            (batch) async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              rows += batch.length;
              expect(batch.single['v'], 7);
            },
            parameters: const {'value': 7},
            fetchSize: 1,
          );
          _confirmedVoid(result, 'gateway_stream');
          expect(rows, 1);
          expect(gateway.hasActiveStream, isFalse);
        }
      }, tags: ['live']);

      test('transaction coordinator confirms commit and rollback on disposable fixtures', () async {
        final table = 'plug_mig5_tx_${DateTime.now().microsecondsSinceEpoch}';
        final connection = _confirmed(await service.connect(dsn!), 'connect');
        Future<odbc.QueryResult> query(String sql) async =>
            _confirmed(await service.executeQuery(sql, connectionId: connection.id), 'fixture_query');
        final metrics = MetricsCollector();
        final manager = OdbcBatchTransactionManager(service: service, metrics: metrics);
        var created = false;
        try {
          await query('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
          created = true;
          Future<BatchTransactionGuard> begin() async {
            final start = _confirmed(
              await manager.beginIfNeeded(
                connectionId: connection.id,
                transactionEnabled: true,
                lockTimeout: null,
                accessMode: odbc.TransactionAccessMode.readWrite,
              ),
              'begin',
            );
            return BatchTransactionGuard(start.transactionId);
          }

          final committed = await begin();
          await query('INSERT INTO $table (id) VALUES (1)');
          _confirmedVoid(await manager.commit(connectionId: connection.id, guard: committed), 'commit');
          expect(committed.state, BatchTransactionState.committed);
          final rolledBack = await begin();
          await query('INSERT INTO $table (id) VALUES (2)');
          _confirmedVoid(await rolledBack.rollback((id) => manager.rollbackIfNeeded(connection.id, id)), 'rollback');
          expect(rolledBack.rollbackConfirmed, isTrue);
          expect((await query('SELECT COUNT(*) AS n FROM $table')).rows.single.single, 1);
        } finally {
          if (created) await query('DROP TABLE $table');
          _confirmedVoid(await service.disconnect(connection.id), 'disconnect');
        }
      }, tags: ['live']);

      test('atomic bulk preserves Unicode/NULL and rolls back a partial failed chunk', () async {
        final table = 'plug_mig5_bulk_${DateTime.now().microsecondsSinceEpoch}';
        final connection = _confirmed(await service.connect(dsn!), 'connect');
        Future<odbc.QueryResult> query(String sql) async =>
            _confirmed(await service.executeQuery(sql, connectionId: connection.id), 'fixture_query');
        final metrics = MetricsCollector();
        final manager = OdbcGatewayConnectionManager(
          service: service,
          connectionPool: OdbcConnectionPool(service, settings),
          directConnectionLimiter: DirectOdbcConnectionLimiter(
            maxConcurrent: 2,
            acquireTimeout: const Duration(seconds: 5),
          ),
          metrics: metrics,
        );
        final executor = OdbcBulkInsertExecutor(
          connectionManager: manager,
          optionsResolver: OdbcConnectionOptionsResolver(settings),
          service: service,
          metrics: metrics,
          settings: settings,
        );
        const columns = [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
          BulkInsertColumn(name: 'note', type: BulkInsertColumnType.text, nullable: true, maxLen: 128),
        ];
        var created = false;
        try {
          await query('CREATE TABLE $table (id INTEGER PRIMARY KEY, note NVARCHAR(128) NULL)');
          created = true;
          _confirmed(
            await executor.executeDirect(
              BulkInsertRequest(
                table: table,
                columns: columns,
                rows: const [
                  [1, 'ação 漢字'],
                  [2, null],
                ],
              ),
              dsn,
              requireAtomic: true,
              timeout: const Duration(seconds: 15),
            ),
            'atomic_bulk',
          );
          final data = await query('SELECT id, note FROM $table ORDER BY id');
          expect(data.rows, [
            [1, 'ação 漢字'],
            [2, null],
          ]);
          final failed = await executor.executeDirect(
            BulkInsertRequest(
              table: table,
              columns: columns,
              rows: const [
                [3, 'must roll back'],
                [3, 'duplicate'],
              ],
            ),
            dsn,
            requireAtomic: true,
            timeout: const Duration(seconds: 15),
          );
          expect(failed.isError(), isTrue);
          expect((await query('SELECT COUNT(*) AS n FROM $table')).rows.single.single, 2);
        } finally {
          if (created) await query('DROP TABLE $table');
          _confirmedVoid(await service.disconnect(connection.id), 'disconnect');
        }
      }, tags: ['live']);

      test('multiple cursors preserve order across continuation batches', () async {
        final connection = _confirmed(await service.connect(dsn!), 'connect');
        try {
          const sql = 'SELECT 1 AS v UNION ALL SELECT 2 AS v; SELECT 3 AS v';
          final result = _confirmed(
            await collectStreamQueryMulti(
              service,
              connection.id,
              driver == 'SQL Anywhere' ? 'BEGIN $sql; END' : sql,
              fetchSize: 1,
            ),
            'multi_result',
          );
          final cursors = result.items
              .where((item) => item.resultSet != null)
              .map((item) => item.resultSet!.rows)
              .toList();
          expect(cursors, [
            [
              [1],
              [2],
            ],
            [
              [3],
            ],
          ]);
        } finally {
          _confirmedVoid(await service.disconnect(connection.id), 'disconnect');
        }
      }, tags: ['live']);
    }, skip: dsn == null || dsn.isEmpty ? '$driver DSN absent: homologation pending' : false);
  }
}

T _confirmed<T extends Object>(Result<T> result, String operation) {
  if (result.isError()) {
    final error = result.exceptionOrNull()!;
    fail(
      '$operation failed: type=${error.runtimeType}, '
      'code=${OdbcErrorInspector.code(error)}, sqlstate=${OdbcErrorInspector.sqlState(error)}, '
      'outcome_unknown=${OdbcErrorInspector.outcomeUnknown(error)}',
    );
  }
  return result.getOrThrow();
}

void _confirmedVoid(Result<void> result, String operation) {
  if (result.isError()) {
    final error = result.exceptionOrNull()!;
    fail(
      '$operation failed: type=${error.runtimeType}, '
      'code=${OdbcErrorInspector.code(error)}, sqlstate=${OdbcErrorInspector.sqlState(error)}, '
      'outcome_unknown=${OdbcErrorInspector.outcomeUnknown(error)}',
    );
  }
}
