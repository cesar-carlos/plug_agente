import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_row_assertions.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

const String _tableName = 'plug_agente_e2e_dml_bulk';

/// E2E: large DML — create table, mass INSERT in chunked `sql.executeBatch`,
/// UPDATE all, DELETE all, DROP table. Timings per phase (opt-in
/// `ODBC_E2E_DML_BULK_TESTS=true`, default 50k rows, chunk 1000).
void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final enabled = E2EEnv.odbcE2eDmlBulkTests;

  final skipMessage = !dsnValid
      ? 'Defina ODBC_E2E_RPC_DSN ou ODBC_TEST_DSN / ODBC_DSN, ODBC_TEST_DSN_SQL_SERVER '
            'ou ODBC_TEST_DSN_POSTGRESQL no .env.'
      : !enabled
      ? 'Defina ODBC_E2E_DML_BULK_TESTS=true no .env para o teste de carga (50k+ linhas, demorado).'
      : null;

  group('ODBC DML bulk load (live E2E)', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;
    late OdbcE2eCoverageSql sql;
    var createMs = 0;

    setUpAll(() async {
      if (!dsnValid || !enabled) {
        return;
      }
      final connectionString = dsn;
      sql = OdbcE2eCoverageSql(
        detectOdbcE2eDialect(connectionString),
        tableName: _tableName,
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

      final swDdl = Stopwatch()..start();
      final create = await opened.gateway.executeNonQuery(
        sql.createTable,
        null,
      );
      swDdl.stop();
      createMs = swDdl.elapsedMilliseconds;
      expect(create.isSuccess(), isTrue, reason: 'create table: $create');

      developer.log(
        'DML bulk: CREATE TABLE ${swDdl.elapsedMilliseconds} ms',
        name: 'e2e.odbc_dml_bulk',
      );
      final maxCreate = E2EEnv.odbcE2eDmlBulkMaxMsCreate;
      if (maxCreate != null) {
        expect(
          swDdl.elapsedMilliseconds,
          lessThanOrEqualTo(maxCreate),
          reason: 'DDL slower than ODBC_E2E_DML_BULK_MAX_MS_CREATE=$maxCreate',
        );
      }

      isReady = true;
    });

    tearDownAll(() async {
      final h = harness;
      if (h == null) {
        return;
      }
      await h.gateway.executeNonQuery(sql.dropTableIfExists, null);
      await h.shutdown();
    });

    test(
      'should create, bulk insert, update, delete, and drop with phase timings',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or bulk E2E not enabled',
        );
        final h = harness!;
        final phaseTimings = <String, int>{'create_ms': createMs};

        final totalRows = E2EEnv.odbcE2eDmlBulkRowCount;
        final transportLimits = TransportLimits(
          maxBatchSize: E2EEnv.odbcE2eDmlBulkChunkSize,
          maxRows: totalRows + 200,
        );

        final swInsert = Stopwatch()..start();
        final bulkInsertReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.bulkInsert',
          id: 'e2e-dml-bulk-insert',
          params: _buildBulkInsertParams(
            tableName: sql.tableName,
            rowCount: totalRows,
          ),
        );
        final insertResp = await h.dispatcher.dispatch(
          bulkInsertReq,
          'e2e-agent',
          limits: transportLimits,
        );
        expect(insertResp.isSuccess, isTrue, reason: '${insertResp.error}');
        final insertMap = insertResp.result! as Map<String, dynamic>;
        expect(insertMap['inserted_rows'], totalRows);
        swInsert.stop();
        phaseTimings['insert_ms'] = swInsert.elapsedMilliseconds;
        developer.log(
          'DML bulk: native bulk INSERT total $totalRows rows in '
          '${swInsert.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_bulk',
        );
        final maxIns = E2EEnv.odbcE2eDmlBulkMaxMsInsertOrDefault;
        expect(
          swInsert.elapsedMilliseconds,
          lessThanOrEqualTo(maxIns),
          reason: 'insert slower than ODBC_E2E_DML_BULK_MAX_MS_INSERT/default=$maxIns',
        );

        final countReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-dml-bulk-count',
          params: <String, dynamic>{
            'sql': sql.countAll,
            'options': <String, dynamic>{'max_rows': 8},
          },
        );
        final countResp = await h.dispatcher.dispatch(
          countReq,
          'e2e-agent',
          limits: transportLimits,
        );
        expect(countResp.isSuccess, isTrue, reason: '${countResp.error}');
        final countMap = countResp.result! as Map<String, dynamic>;
        final rows = countMap['rows'] as List<dynamic>?;
        expect(rows, isNotNull);
        expect(rows, isNotEmpty);
        final n = e2eFirstNumericForKeyContaining(
          rows!.first as Map<String, dynamic>,
          'count',
        );
        expect(n, totalRows, reason: 'row count after bulk insert');

        final swUpdate = Stopwatch()..start();
        final updateReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-dml-bulk-update',
          params: <String, dynamic>{
            'sql': sql.updateAllRowsBumpAmt,
          },
        );
        final updateResp = await h.dispatcher.dispatch(
          updateReq,
          'e2e-agent',
          limits: transportLimits,
        );
        swUpdate.stop();
        phaseTimings['update_ms'] = swUpdate.elapsedMilliseconds;
        expect(updateResp.isSuccess, isTrue, reason: '${updateResp.error}');
        developer.log(
          'DML bulk: UPDATE all ($totalRows rows) ${swUpdate.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_bulk',
        );
        final maxUp = E2EEnv.odbcE2eDmlBulkMaxMsUpdate;
        if (maxUp != null) {
          expect(
            swUpdate.elapsedMilliseconds,
            lessThanOrEqualTo(maxUp),
            reason: 'update slower than ODBC_E2E_DML_BULK_MAX_MS_UPDATE=$maxUp',
          );
        }

        final swDelete = Stopwatch()..start();
        final deleteReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-dml-bulk-delete',
          params: <String, dynamic>{
            'sql': sql.deleteAllRows,
          },
        );
        final deleteResp = await h.dispatcher.dispatch(
          deleteReq,
          'e2e-agent',
          limits: transportLimits,
        );
        swDelete.stop();
        phaseTimings['delete_ms'] = swDelete.elapsedMilliseconds;
        expect(deleteResp.isSuccess, isTrue, reason: '${deleteResp.error}');
        developer.log(
          'DML bulk: DELETE all rows ${swDelete.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_bulk',
        );
        final maxDel = E2EEnv.odbcE2eDmlBulkMaxMsDelete;
        if (maxDel != null) {
          expect(
            swDelete.elapsedMilliseconds,
            lessThanOrEqualTo(maxDel),
            reason: 'delete slower than ODBC_E2E_DML_BULK_MAX_MS_DELETE=$maxDel',
          );
        }

        final swUserDrop = Stopwatch()..start();
        final userDrop = await h.gateway.executeNonQuery(
          sql.dropTableIfExists,
          null,
        );
        swUserDrop.stop();
        phaseTimings['drop_ms'] = swUserDrop.elapsedMilliseconds;
        expect(userDrop.isSuccess(), isTrue, reason: 'user drop: $userDrop');
        developer.log(
          'E2E_DML_BULK_PHASE_TIMINGS '
          '${jsonEncode({
            'rows': totalRows,
            'method': 'odbc_fast.bulkInsert',
            ...phaseTimings,
          })}',
          name: 'e2e.odbc_dml_bulk',
        );
        developer.log(
          'DML bulk: DROP TABLE (end of test) ${swUserDrop.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_bulk',
        );
        final maxDrop = E2EEnv.odbcE2eDmlBulkMaxMsDrop;
        if (maxDrop != null) {
          expect(
            swUserDrop.elapsedMilliseconds,
            lessThanOrEqualTo(maxDrop),
            reason: 'drop slower than ODBC_E2E_DML_BULK_MAX_MS_DROP=$maxDrop',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: skipMessage,
      tags: const ['live', 'slow', 'perf'],
    );
  });
}

Map<String, dynamic> _buildBulkInsertParams({
  required String tableName,
  required int rowCount,
}) {
  final rows = <List<dynamic>>[];

  for (var i = 1; i <= rowCount; i++) {
    final day = (i % 28) + 1;
    final isActive = i.isEven ? 1 : 0;
    rows.add([
      i,
      'b$i',
      (1.0 + (i % 100) * 0.01).toStringAsFixed(2),
      '2024-01-${day.toString().padLeft(2, '0')}T00:00:00Z',
      '2024-06-01T12:00:00Z',
      isActive,
    ]);
  }

  return {
    'table': tableName,
    'columns': const [
      {'name': 'id', 'type': 'i32'},
      {'name': 'code', 'type': 'text', 'max_len': 40},
      {'name': 'amt', 'type': 'decimal', 'max_len': 16},
      {'name': 'birth_date', 'type': 'timestamp'},
      {'name': 'ts_col', 'type': 'timestamp'},
      {'name': 'is_active', 'type': 'i32'},
    ],
    'rows': rows,
  };
}
