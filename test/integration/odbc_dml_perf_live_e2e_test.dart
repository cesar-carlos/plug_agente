import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

/// E2E: measure wall time for bulk INSERT (via `sql.executeBatch`), UPDATE all,
/// DELETE all on a real database. Opt-in (`ODBC_E2E_DML_PERF_TESTS=true`) so
/// default `flutter test` stays fast.
///
/// Uses the same DSN resolution as `odbc_rpc_execute_coverage_live_e2e_test`
/// (`E2EEnv.odbcE2eRpcConnectionString`).
void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final enabled = E2EEnv.odbcE2eDmlPerfTests;

  final skipMessage = !dsnValid
      ? 'Defina ODBC_E2E_RPC_DSN ou ODBC_TEST_DSN / ODBC_DSN, ODBC_TEST_DSN_SQL_SERVER '
            'ou ODBC_TEST_DSN_POSTGRESQL no .env.'
      : !enabled
          ? 'Defina ODBC_E2E_DML_PERF_TESTS=true no .env para este teste de desempenho DML.'
          : null;

  group('ODBC DML performance (live E2E)', () {
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
        tableName: 'plug_agente_e2e_dml_perf',
      );
      final opened = await OdbcE2eRpcHarness.open(
        connectionString,
        sql.dialect,
      );
      if (opened == null) {
        return;
      }
      harness = opened;

      final drop = await opened.gateway.executeNonQuery(
        sql.dropTableIfExists,
        null,
      );
      expect(drop.isSuccess(), isTrue, reason: 'drop table: $drop');

      final create = await opened.gateway.executeNonQuery(
        sql.createTable,
        null,
      );
      expect(create.isSuccess(), isTrue, reason: 'create table: $create');

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
      'should complete bulk insert, update-all, and delete-all within optional limits',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or env not configured for DML perf E2E',
        );
        final h = harness!;
        final rowCount = E2EEnv.odbcE2eDmlPerfRowCount;

        final insertCommands = <Map<String, dynamic>>[];
        for (var i = 1; i <= rowCount; i++) {
          insertCommands.add({
            'sql': sql.insertRow(
              id: i,
              code: 'p$i',
              amt: 1.0 + (i % 100) * 0.01,
              birthDate: '2024-01-${(i % 28) + 1}',
              ts: '2024-06-01 12:00:00',
              isActive: i.isEven,
            ),
          });
        }

        final swInsert = Stopwatch()..start();
        final insertReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-dml-perf-insert',
          params: {
            'commands': insertCommands,
            'options': {
              'transaction': false,
              'max_rows': rowCount + 64,
            },
          },
        );
        final insertResp = await h.dispatcher.dispatch(
          insertReq,
          'e2e-agent',
          limits: TransportLimits(
            maxBatchSize: math.max(TransportLimits.defaultMaxBatchSize, rowCount),
            maxRows: rowCount + 64,
          ),
        );
        swInsert.stop();

        expect(insertResp.isSuccess, isTrue, reason: '${insertResp.error}');
        final insertMap = insertResp.result! as Map<String, dynamic>;
        expect(insertMap['failed_commands'], 0);
        expect(insertMap['successful_commands'], rowCount);

        developer.log(
          'DML perf: insert batch ($rowCount rows) ${swInsert.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_perf',
        );
        final maxIns = E2EEnv.odbcE2eDmlPerfMaxMsInsert;
        if (maxIns != null) {
          expect(
            swInsert.elapsedMilliseconds,
            lessThanOrEqualTo(maxIns),
            reason: 'insert phase slower than ODBC_E2E_DML_PERF_MAX_MS_INSERT=$maxIns',
          );
        }

        final swUpdate = Stopwatch()..start();
        final updateReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-dml-perf-update',
          params: <String, dynamic>{
            'sql': sql.updateAllRowsBumpAmt,
          },
        );
        final updateResp = await h.dispatcher.dispatch(updateReq, 'e2e-agent');
        swUpdate.stop();

        expect(updateResp.isSuccess, isTrue, reason: '${updateResp.error}');
        developer.log(
          'DML perf: update all ($rowCount rows) ${swUpdate.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_perf',
        );
        final maxUp = E2EEnv.odbcE2eDmlPerfMaxMsUpdate;
        if (maxUp != null) {
          expect(
            swUpdate.elapsedMilliseconds,
            lessThanOrEqualTo(maxUp),
            reason: 'update phase slower than ODBC_E2E_DML_PERF_MAX_MS_UPDATE=$maxUp',
          );
        }

        final swDelete = Stopwatch()..start();
        final deleteReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-dml-perf-delete',
          params: <String, dynamic>{
            'sql': sql.deleteAllRows,
          },
        );
        final deleteResp = await h.dispatcher.dispatch(deleteReq, 'e2e-agent');
        swDelete.stop();

        expect(deleteResp.isSuccess, isTrue, reason: '${deleteResp.error}');
        developer.log(
          'DML perf: delete all ${swDelete.elapsedMilliseconds} ms',
          name: 'e2e.odbc_dml_perf',
        );
        final maxDel = E2EEnv.odbcE2eDmlPerfMaxMsDelete;
        if (maxDel != null) {
          expect(
            swDelete.elapsedMilliseconds,
            lessThanOrEqualTo(maxDel),
            reason: 'delete phase slower than ODBC_E2E_DML_PERF_MAX_MS_DELETE=$maxDel',
          );
        }
      },
      skip: skipMessage,
    );
  });
}
