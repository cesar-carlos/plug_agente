import 'dart:developer' as developer;
import 'dart:math' as math;

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

        final totalRows = E2EEnv.odbcE2eDmlBulkRowCount;
        final chunkSize = E2EEnv.odbcE2eDmlBulkChunkSize;
        final transportLimits = TransportLimits(
          maxBatchSize: chunkSize,
          maxRows: totalRows + 200,
        );

        final swInsert = Stopwatch()..start();
        var inserted = 0;
        var batchIndex = 0;
        while (inserted < totalRows) {
          final take = math.min(chunkSize, totalRows - inserted);
          final commands = <Map<String, dynamic>>[];
          for (var j = 0; j < take; j++) {
            final i = inserted + j + 1;
            commands.add({
              'sql': sql.insertRow(
                id: i,
                code: 'b$i',
                amt: 1.0 + (i % 100) * 0.01,
                birthDate: '2024-01-${(i % 28) + 1}',
                ts: '2024-06-01 12:00:00',
                isActive: i.isEven,
              ),
            });
          }
          final insertReq = RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.executeBatch',
            id: 'e2e-dml-bulk-$batchIndex',
            params: {
              'commands': commands,
              'options': {
                'transaction': false,
                'max_rows': take + 8,
              },
            },
          );
          final insertResp = await h.dispatcher.dispatch(
            insertReq,
            'e2e-agent',
            limits: transportLimits,
          );
          expect(insertResp.isSuccess, isTrue, reason: 'batch $batchIndex: ${insertResp.error}');
          final m = insertResp.result! as Map<String, dynamic>;
          expect(m['failed_commands'], 0);
          expect(m['successful_commands'], take);
          inserted += take;
          batchIndex++;
          if (batchIndex % 10 == 0 || inserted >= totalRows) {
            developer.log(
              'DML bulk: inserted $inserted / $totalRows (batch size $chunkSize)',
              name: 'e2e.odbc_dml_bulk',
            );
          }
        }
        swInsert.stop();
        developer.log(
          'DML bulk: INSERT total $inserted rows in ${swInsert.elapsedMilliseconds} ms '
          '($batchIndex batches, ~${(swInsert.elapsedMilliseconds / math.max(1, batchIndex)).toStringAsFixed(1)} ms/batch)',
          name: 'e2e.odbc_dml_bulk',
        );
        final maxIns = E2EEnv.odbcE2eDmlBulkMaxMsInsert;
        if (maxIns != null) {
          expect(
            swInsert.elapsedMilliseconds,
            lessThanOrEqualTo(maxIns),
            reason: 'insert slower than ODBC_E2E_DML_BULK_MAX_MS_INSERT=$maxIns',
          );
        }

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
        expect(userDrop.isSuccess(), isTrue, reason: 'user drop: $userDrop');
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
    );
  });
}
