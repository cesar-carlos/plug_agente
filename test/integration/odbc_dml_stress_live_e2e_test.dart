import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_row_assertions.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

/// E2E: extreme DML stress — CREATE TABLE (unique name), repeated parallel
/// INSERT / UPDATE / DELETE cycles, DROP TABLE. Opt-in via
/// `ODBC_E2E_DML_STRESS_TESTS=true`.
///
/// Rows for the queued-gateway scenario (batched via `executeBatch`, not per-row RPC).
const int _queuedGatewayStressRowCap = 2000;

void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final enabled = E2EEnv.odbcE2eDmlStressTests;

  final skipMessage = !dsnValid
      ? 'Defina ODBC_E2E_RPC_DSN ou ODBC_TEST_DSN / ODBC_DSN, ODBC_TEST_DSN_SQL_SERVER '
            'ou ODBC_TEST_DSN_POSTGRESQL no .env.'
      : !enabled
      ? 'Defina ODBC_E2E_DML_STRESS_TESTS=true no .env para o teste de stress DML (CREATE/INSERT/UPDATE/DELETE/DROP).'
      : null;

  group('ODBC DML stress (live E2E)', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;
    late OdbcE2eCoverageSql sql;
    late String tableName;

    setUpAll(() async {
      if (!dsnValid || !enabled) {
        return;
      }
      final connectionString = dsn;
      tableName = odbcE2eUniqueTableName();
      sql = OdbcE2eCoverageSql(
        detectOdbcE2eDialect(connectionString),
        tableName: tableName,
      );
      final opened = await OdbcE2eRpcHarness.open(
        connectionString,
        sql.dialect,
      );
      if (opened == null) {
        return;
      }
      harness = opened;

      final preDrop = await opened.gateway.executeNonQuery(
        sql.dropTableIfExists,
        null,
      );
      expect(preDrop.isSuccess(), isTrue, reason: 'pre drop: $preDrop');

      final create = await opened.gateway.executeNonQuery(
        sql.createTable,
        null,
      );
      expect(create.isSuccess(), isTrue, reason: 'create table: $create');

      developer.log(
        'DML stress: CREATE TABLE $tableName',
        name: 'e2e.odbc_dml_stress',
      );
      isReady = true;
    });

    tearDownAll(() async {
      final h = harness;
      if (h == null) {
        return;
      }
      final drop = await h.gateway.executeNonQuery(sql.dropTableIfExists, null);
      if (drop.isError()) {
        developer.log(
          'DML stress: tearDown DROP failed: $drop',
          name: 'e2e.odbc_dml_stress',
          level: 900,
        );
      }
      await h.shutdown();
    });

    test(
      'should survive repeated parallel insert/update/delete cycles without pool leaks',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or stress E2E not enabled',
        );
        final h = harness!;
        final rowCount = E2EEnv.odbcE2eDmlStressRowCount;
        final iterations = E2EEnv.odbcE2eDmlStressIterations;
        final concurrency = E2EEnv.odbcE2eDmlStressConcurrency;
        final chunkSize = E2EEnv.odbcE2eDmlStressBatchChunkSize;
        final maxMsPerIteration = E2EEnv.odbcE2eDmlStressMaxMsPerIteration;
        final transportLimits = TransportLimits(
          maxBatchSize: chunkSize,
          maxRows: rowCount + 200,
        );

        final iterationTimings = <Map<String, dynamic>>[];

        for (var iteration = 0; iteration < iterations; iteration++) {
          final swIteration = Stopwatch()..start();

          final swInsert = Stopwatch()..start();
          await _parallelInsertBatch(
            harness: h,
            sql: sql,
            rowCount: rowCount,
            concurrency: concurrency,
            chunkSize: chunkSize,
            transportLimits: transportLimits,
            iteration: iteration,
          );
          swInsert.stop();

          final countAfterInsert = await _countRows(h, sql, transportLimits);
          expect(countAfterInsert, rowCount, reason: 'iteration $iteration after insert');

          final swUpdate = Stopwatch()..start();
          await _parallelUpdateByRange(
            harness: h,
            sql: sql,
            rowCount: rowCount,
            concurrency: concurrency,
            transportLimits: transportLimits,
            iteration: iteration,
          );
          swUpdate.stop();

          final swDelete = Stopwatch()..start();
          await _parallelDeleteByRange(
            harness: h,
            sql: sql,
            rowCount: rowCount,
            concurrency: concurrency,
            transportLimits: transportLimits,
            iteration: iteration,
          );
          swDelete.stop();

          final countAfterDelete = await _countRows(h, sql, transportLimits);
          expect(countAfterDelete, 0, reason: 'iteration $iteration after delete');

          swIteration.stop();
          final timing = {
            'iteration': iteration,
            'insert_ms': swInsert.elapsedMilliseconds,
            'update_ms': swUpdate.elapsedMilliseconds,
            'delete_ms': swDelete.elapsedMilliseconds,
            'total_ms': swIteration.elapsedMilliseconds,
            'rows': rowCount,
            'concurrency': concurrency,
          };
          iterationTimings.add(timing);

          final insertMs = swInsert.elapsedMilliseconds;
          final updateMs = swUpdate.elapsedMilliseconds;
          final deleteMs = swDelete.elapsedMilliseconds;

          developer.log(
            'DML stress iteration $iteration: '
            'insert=${insertMs}ms '
            'update=${updateMs}ms '
            'delete=${deleteMs}ms',
            name: 'e2e.odbc_dml_stress',
          );

          if (maxMsPerIteration != null) {
            expect(
              swIteration.elapsedMilliseconds,
              lessThanOrEqualTo(maxMsPerIteration),
              reason: 'iteration $iteration exceeded ODBC_E2E_DML_STRESS_MAX_MS_PER_ITERATION=$maxMsPerIteration',
            );
          }
        }

        final active = await h.connectionPool.getActiveCount();
        expect(active.isSuccess(), isTrue, reason: '$active');
        expect(active.getOrThrow(), 0);

        developer.log(
          'E2E_DML_STRESS_ITERATION_TIMINGS '
          '${jsonEncode({
            'table': tableName,
            'dialect': sql.dialect.name,
            'iterations': iterationTimings,
          })}',
          name: 'e2e.odbc_dml_stress',
        );
      },
      timeout: const Timeout(Duration(minutes: 45)),
      skip: skipMessage,
      tags: const ['live', 'slow', 'perf'],
    );

    test(
      'should route concurrent DML through QueuedDatabaseGateway without stuck leases',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or stress E2E not enabled',
        );
        final h = harness!;
        final rowCount = math.min(
          E2EEnv.odbcE2eDmlStressRowCount,
          _queuedGatewayStressRowCap,
        );
        final concurrency = E2EEnv.odbcE2eDmlStressConcurrency;
        final chunkSize = E2EEnv.odbcE2eDmlStressBatchChunkSize;
        final queuedGateway = QueuedDatabaseGateway(
          delegate: h.gateway,
          queue: SqlExecutionQueue(
            maxQueueSize: E2EEnv.odbcE2eDmlStressQueueSize,
            maxConcurrentWorkers: E2EEnv.odbcE2eDmlStressWorkers,
            metricsCollector: h.metrics,
          ),
        );

        try {
          final sw = Stopwatch()..start();
          final insertFutures = _buildIdRanges(rowCount, concurrency).map((range) async {
            final commands = <SqlCommand>[];
            for (var id = range.start; id <= range.end; id++) {
              commands.add(
                SqlCommand(
                  sql: sql.insertRow(
                    id: id,
                    code: 'q$id',
                    amt: 1.0 + (id % 50) * 0.01,
                    birthDate: '2024-02-${(id % 28) + 1}',
                    ts: '2024-06-01 12:00:00',
                    isActive: id.isEven,
                  ),
                ),
              );
            }

            for (var offset = 0; offset < commands.length; offset += chunkSize) {
              final end = math.min(offset + chunkSize, commands.length);
              final chunk = commands.sublist(offset, end);
              final result = await queuedGateway.executeBatch(
                'e2e-agent',
                chunk,
                options: SqlExecutionOptions(
                  transaction: true,
                  maxRows: chunk.length + 16,
                ),
              );
              expect(result.isSuccess(), isTrue, reason: 'insert range ${range.start}: $result');
              final outcomes = result.getOrThrow();
              expect(outcomes.every((item) => item.ok), isTrue, reason: '$outcomes');
            }
          }).toList();

          await Future.wait(insertFutures);

          final updateFutures = _buildIdRanges(rowCount, concurrency).map((range) {
            return queuedGateway.executeNonQuery(
              _updateByIdRangeSql(sql, range.start, range.end),
              null,
            );
          }).toList();
          final updateResults = await Future.wait(updateFutures);
          for (final result in updateResults) {
            expect(result.isSuccess(), isTrue, reason: '$result');
          }

          final deleteFutures = _buildIdRanges(rowCount, concurrency).map((range) {
            return queuedGateway.executeNonQuery(
              _deleteByIdRangeSql(sql, range.start, range.end),
              null,
            );
          }).toList();
          final deleteResults = await Future.wait(deleteFutures);
          for (final result in deleteResults) {
            expect(result.isSuccess(), isTrue, reason: '$result');
          }

          sw.stop();
          final active = await h.connectionPool.getActiveCount();
          expect(active.isSuccess(), isTrue, reason: '$active');
          expect(active.getOrThrow(), 0);

          developer.log(
            'E2E_DML_STRESS_QUEUED_TIMING '
            '${jsonEncode({
              'table': tableName,
              'rows': rowCount,
              'concurrency': concurrency,
              'queue_size': E2EEnv.odbcE2eDmlStressQueueSize,
              'workers': E2EEnv.odbcE2eDmlStressWorkers,
              'elapsed_ms': sw.elapsedMilliseconds,
            })}',
            name: 'e2e.odbc_dml_stress',
          );
        } finally {
          queuedGateway.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 15)),
      skip: skipMessage,
      tags: const ['live', 'slow'],
    );
  });
}

class _IdRange {
  const _IdRange(this.start, this.end);

  final int start;
  final int end;
}

List<_IdRange> _buildIdRanges(int rowCount, int concurrency) {
  final workers = math.max(1, concurrency);
  final ranges = <_IdRange>[];
  var start = 1;
  final baseSize = rowCount ~/ workers;
  var remainder = rowCount % workers;

  for (var worker = 0; worker < workers; worker++) {
    final size = baseSize + (remainder > 0 ? 1 : 0);
    if (remainder > 0) {
      remainder--;
    }
    if (size <= 0) {
      continue;
    }
    final end = start + size - 1;
    ranges.add(_IdRange(start, end));
    start = end + 1;
  }
  return ranges;
}

String _updateByIdRangeSql(OdbcE2eCoverageSql sql, int startId, int endId) {
  return 'UPDATE ${sql.tableName} SET amt = amt + 0.0001 WHERE id >= $startId AND id <= $endId';
}

String _deleteByIdRangeSql(OdbcE2eCoverageSql sql, int startId, int endId) {
  return 'DELETE FROM ${sql.tableName} WHERE id >= $startId AND id <= $endId';
}

Future<void> _parallelInsertBatch({
  required OdbcE2eRpcHarness harness,
  required OdbcE2eCoverageSql sql,
  required int rowCount,
  required int concurrency,
  required int chunkSize,
  required TransportLimits transportLimits,
  required int iteration,
}) async {
  final ranges = _buildIdRanges(rowCount, concurrency);
  final futures = ranges.map((range) async {
    final commands = <Map<String, dynamic>>[];
    for (var id = range.start; id <= range.end; id++) {
      commands.add({
        'sql': sql.insertRow(
          id: id,
          code: 's$id',
          amt: 1.0 + (id % 100) * 0.01,
          birthDate: '2024-03-${(id % 28) + 1}',
          ts: '2024-06-01 12:00:00',
          isActive: id.isOdd,
        ),
      });
    }

    for (var offset = 0; offset < commands.length; offset += chunkSize) {
      final end = math.min(offset + chunkSize, commands.length);
      final chunk = commands.sublist(offset, end);
      final req = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.executeBatch',
        id: 'e2e-dml-stress-ins-$iteration-${range.start}-$offset',
        params: {
          'commands': chunk,
          'options': {
            'transaction': true,
            'max_rows': chunk.length + 16,
          },
        },
      );
      final resp = await harness.dispatcher.dispatch(
        req,
        'e2e-agent',
        limits: transportLimits,
      );
      expect(resp.isSuccess, isTrue, reason: '${resp.error}');
      final map = resp.result! as Map<String, dynamic>;
      expect(map['failed_commands'], 0);
      expect(map['successful_commands'], chunk.length);
    }
  });

  await Future.wait(futures);
}

Future<void> _parallelUpdateByRange({
  required OdbcE2eRpcHarness harness,
  required OdbcE2eCoverageSql sql,
  required int rowCount,
  required int concurrency,
  required TransportLimits transportLimits,
  required int iteration,
}) async {
  final ranges = _buildIdRanges(rowCount, concurrency);
  final futures = ranges.map((range) async {
    final req = RpcRequest(
      jsonrpc: '2.0',
      method: 'sql.execute',
      id: 'e2e-dml-stress-upd-$iteration-${range.start}',
      params: <String, dynamic>{
        'sql': _updateByIdRangeSql(sql, range.start, range.end),
      },
    );
    final resp = await harness.dispatcher.dispatch(
      req,
      'e2e-agent',
      limits: transportLimits,
    );
    expect(resp.isSuccess, isTrue, reason: '${resp.error}');
  });

  await Future.wait(futures);
}

Future<void> _parallelDeleteByRange({
  required OdbcE2eRpcHarness harness,
  required OdbcE2eCoverageSql sql,
  required int rowCount,
  required int concurrency,
  required TransportLimits transportLimits,
  required int iteration,
}) async {
  final ranges = _buildIdRanges(rowCount, concurrency);
  final futures = ranges.map((range) async {
    final req = RpcRequest(
      jsonrpc: '2.0',
      method: 'sql.execute',
      id: 'e2e-dml-stress-del-$iteration-${range.start}',
      params: <String, dynamic>{
        'sql': _deleteByIdRangeSql(sql, range.start, range.end),
      },
    );
    final resp = await harness.dispatcher.dispatch(
      req,
      'e2e-agent',
      limits: transportLimits,
    );
    expect(resp.isSuccess, isTrue, reason: '${resp.error}');
  });

  await Future.wait(futures);
}

Future<int> _countRows(
  OdbcE2eRpcHarness harness,
  OdbcE2eCoverageSql sql,
  TransportLimits transportLimits,
) async {
  final req = RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.execute',
    id: 'e2e-dml-stress-count',
    params: <String, dynamic>{
      'sql': sql.countAll,
      'options': <String, dynamic>{'max_rows': 8},
    },
  );
  final resp = await harness.dispatcher.dispatch(
    req,
    'e2e-agent',
    limits: transportLimits,
  );
  expect(resp.isSuccess, isTrue, reason: '${resp.error}');
  final map = resp.result! as Map<String, dynamic>;
  final rows = map['rows'] as List<dynamic>?;
  expect(rows, isNotNull);
  expect(rows, isNotEmpty);
  final n = e2eFirstNumericForKeyContaining(
    rows!.first as Map<String, dynamic>,
    'count',
  );
  expect(n, isNotNull);
  return n!.toInt();
}
