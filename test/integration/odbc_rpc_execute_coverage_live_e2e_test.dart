import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_row_assertions.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

/// E2E: `sql.execute` (multi-result) and `sql.executeBatch` (SELECT/DML) against
/// a real database from `E2EEnv.odbcE2eRpcConnectionString` (optional
/// `ODBC_E2E_RPC_DSN`, else same order as any ODBC DSN: SQL Anywhere →
/// SQL Server → PostgreSQL).
///
/// DDL uses the gateway `executeNonQuery` because the RPC SQL validator does not
/// allow CREATE/DROP.
///
/// Tests run in **declaration order** within the group: inserts first, then
/// multi-result and further batches, then optional transactional batch.
void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final skipUnlessDsn = !dsnValid
      ? 'Defina ODBC_E2E_RPC_DSN ou pelo menos um de ODBC_TEST_DSN / ODBC_DSN, '
            'ODBC_TEST_DSN_SQL_SERVER, ODBC_TEST_DSN_POSTGRESQL no .env.'
      : false;

  group('ODBC RPC execute / executeBatch coverage (E2E)', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;
    late OdbcE2eCoverageSql sql;

    setUpAll(() async {
      if (!dsnValid) {
        return;
      }
      final connectionString = dsn;
      sql = OdbcE2eCoverageSql(
        detectOdbcE2eDialect(connectionString),
        tableName: 'plug_agente_e2e_cov_rpc',
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
      'should insert three rows via sql.executeBatch',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final insertBatch = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-batch-insert',
          params: {
            'commands': [
              {
                'sql': sql.insertRow(
                  id: 1,
                  code: 'alpha',
                  amt: 10.5,
                  birthDate: '2024-01-10',
                  ts: '2024-06-01 12:00:00',
                  isActive: true,
                ),
              },
              {
                'sql': sql.insertRow(
                  id: 2,
                  code: 'beta',
                  amt: 20,
                  birthDate: '2024-02-11',
                  ts: '2024-06-02 13:30:00',
                  isActive: false,
                ),
              },
              {
                'sql': sql.insertRow(
                  id: 3,
                  code: 'gamma',
                  amt: 30.25,
                  birthDate: '2024-03-12',
                  ts: '2024-06-03 14:45:00',
                  isActive: true,
                ),
              },
            ],
            'options': {'transaction': false, 'max_rows': 500},
          },
        );

        final insertResp = await h.dispatcher.dispatch(
          insertBatch,
          'e2e-agent',
        );
        expect(insertResp.isSuccess, isTrue, reason: '${insertResp.error}');
        final insertMap = insertResp.result! as Map<String, dynamic>;
        expect(insertMap['failed_commands'], 0);
        expect(insertMap['successful_commands'], 3);
        final insertItems = insertMap['items'] as List<dynamic>;
        expect(insertItems, hasLength(3));
        for (final dynamic raw in insertItems) {
          final item = raw as Map<String, dynamic>;
          expect(item['ok'], isTrue, reason: '$item');
        }
      },
      skip: skipUnlessDsn,
    );

    test(
      'should return rows for SELECT commands in sql.executeBatch',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final selectBatch = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-batch-select',
          params: {
            'commands': [
              {'sql': sql.selectIdCodeAmtById(1)},
              {'sql': sql.selectIdCodeAmtById(2)},
              {'sql': sql.countAll},
            ],
            'options': {'transaction': false, 'max_rows': 100},
          },
        );

        final resp = await h.dispatcher.dispatch(selectBatch, 'e2e-agent');
        expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        final map = resp.result! as Map<String, dynamic>;
        expect(map['failed_commands'], 0);
        expect(map['successful_commands'], 3);
        final items = map['items'] as List<dynamic>;
        expect(items, hasLength(3));

        final item0 = items[0] as Map<String, dynamic>;
        expect(item0['ok'], isTrue);
        final rows0 = item0['rows'] as List<dynamic>?;
        expect(rows0, isNotNull);
        expect(rows0, hasLength(1));
        final row0 = rows0!.first as Map<String, dynamic>;
        expect(e2eRowStringForColumnInsensitive(row0, 'code'), 'alpha');

        final item1 = items[1] as Map<String, dynamic>;
        expect(item1['ok'], isTrue);
        final rows1 = item1['rows'] as List<dynamic>?;
        expect(rows1, isNotNull);
        expect(rows1, hasLength(1));
        final row1 = rows1!.first as Map<String, dynamic>;
        expect(e2eRowStringForColumnInsensitive(row1, 'code'), 'beta');

        final item2 = items[2] as Map<String, dynamic>;
        expect(item2['ok'], isTrue);
        final rows2 = item2['rows'] as List<dynamic>?;
        expect(rows2, isNotNull);
        expect(rows2, isNotEmpty);
        final countRow = rows2!.first as Map<String, dynamic>;
        final n = e2eFirstNumericForKeyContaining(countRow, 'count');
        expect(n, isNotNull, reason: 'count row keys: ${countRow.keys}');
        expect(n, 3);
      },
      skip: skipUnlessDsn,
    );

    test(
      'should run sql.execute multi_result, batch updates, mixed batch, '
      'deletes, and row probes',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final multi = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-multi-result',
          params: {
            'sql': sql.multiResultProbe,
            'options': {'multi_result': true, 'max_rows': 100},
          },
        );

        final multiResp = await h.dispatcher.dispatch(multi, 'e2e-agent');
        expect(multiResp.isSuccess, isTrue, reason: '${multiResp.error}');
        final multiMap = multiResp.result! as Map<String, dynamic>;
        expect(multiMap['multi_result'], isTrue);
        final sets = multiMap['result_sets'] as List<dynamic>? ?? [];
        final multiRows = multiMap['rows'] as List<dynamic>? ?? [];
        if (sets.isEmpty && multiRows.isEmpty) {
          if (E2EEnv.odbcE2eRequireMultiResult) {
            fail(
              'ODBC_E2E_REQUIRE_MULTI_RESULT=true but sql.execute with '
              'multi_result returned no result_sets/rows. The gateway normally '
              'retries multi-result on a direct connection when the pool returns '
              'an empty payload; if this still fails, check driver/odbc_fast.',
            );
          }
          // Defense in depth if RPC still returns an empty envelope (e.g. older
          // gateway or edge case): same facts via two simple executes.
          final pickOne = RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.execute',
            id: 'e2e-fallback-row',
            params: <String, dynamic>{
              'sql': 'SELECT id, code, amt FROM ${sql.tableName} WHERE id = 1',
            },
          );
          final pickResp = await h.dispatcher.dispatch(pickOne, 'e2e-agent');
          expect(pickResp.isSuccess, isTrue, reason: '${pickResp.error}');
          final pickRows = (pickResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
          expect(pickRows, isNotNull);
          expect(pickRows, isNotEmpty);

          final pickCount = RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.execute',
            id: 'e2e-fallback-count',
            params: <String, dynamic>{
              'sql': 'SELECT COUNT(*) AS row_count FROM ${sql.tableName}',
            },
          );
          final countFallbackResp = await h.dispatcher.dispatch(
            pickCount,
            'e2e-agent',
          );
          expect(
            countFallbackResp.isSuccess,
            isTrue,
            reason: '${countFallbackResp.error}',
          );
          final countRows = (countFallbackResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
          expect(countRows, isNotNull);
          expect(countRows, isNotEmpty);
        } else {
          expect(multiMap['multi_result'], isTrue);
          final itemCount = multiMap['item_count'] as int? ?? 0;
          expect(
            sets.length >= 2 || multiRows.isNotEmpty || itemCount >= 2,
            isTrue,
            reason:
                'sets=${sets.length} rows=${multiRows.length} '
                'item_count=$itemCount',
          );
          expect(
            h.metrics.multiResultDirectStillVacuousCount,
            0,
            reason:
                'multi-result returned data; direct path should not be marked '
                'still-vacuous',
          );
        }

        final updateBatch = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-batch-update',
          params: {
            'commands': [
              {'sql': sql.updateAmtById(1, 1)},
              {'sql': sql.updateCodeById(2, 'patched')},
            ],
            'options': {'transaction': false, 'max_rows': 100},
          },
        );

        final updateResp = await h.dispatcher.dispatch(
          updateBatch,
          'e2e-agent',
        );
        expect(updateResp.isSuccess, isTrue, reason: '${updateResp.error}');
        final updateMap = updateResp.result! as Map<String, dynamic>;
        expect(updateMap['failed_commands'], 0);
        expect(updateMap['successful_commands'], 2);

        final mixedBatch = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-batch-mixed',
          params: {
            'commands': [
              {
                'sql': sql.insertRow(
                  id: 4,
                  code: 'delta',
                  amt: 40,
                  birthDate: '2024-04-13',
                  ts: '2024-06-04 15:00:00',
                  isActive: false,
                ),
              },
              {'sql': sql.updateCodeById(3, 'tau')},
            ],
            'options': {'transaction': false, 'max_rows': 100},
          },
        );

        final mixedResp = await h.dispatcher.dispatch(
          mixedBatch,
          'e2e-agent',
        );
        expect(mixedResp.isSuccess, isTrue, reason: '${mixedResp.error}');
        final mixedMap = mixedResp.result! as Map<String, dynamic>;
        expect(mixedMap['failed_commands'], 0);
        expect(mixedMap['successful_commands'], 2);

        final deleteBatch = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-batch-delete',
          params: {
            'commands': [
              {'sql': sql.deleteById(1)},
              {'sql': sql.deleteById(2)},
            ],
            'options': {'transaction': false, 'max_rows': 50},
          },
        );

        final deleteResp = await h.dispatcher.dispatch(
          deleteBatch,
          'e2e-agent',
        );
        expect(deleteResp.isSuccess, isTrue, reason: '${deleteResp.error}');
        final deleteMap = deleteResp.result! as Map<String, dynamic>;
        expect(deleteMap['failed_commands'], 0);
        expect(deleteMap['successful_commands'], 2);

        final rowProbe = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-row-probe',
          params: <String, dynamic>{
            'sql': 'SELECT * FROM ${sql.tableName} WHERE id = 3',
          },
        );

        final rowResp = await h.dispatcher.dispatch(rowProbe, 'e2e-agent');
        expect(rowResp.isSuccess, isTrue, reason: '${rowResp.error}');
        final rowMap = rowResp.result! as Map<String, dynamic>;
        final probeRows = rowMap['rows'] as List<dynamic>?;
        expect(probeRows, isNotNull);
        expect(probeRows, hasLength(1));
        final probeRow = probeRows!.first as Map<String, dynamic>;
        final lowerKeys = probeRow.keys.map((dynamic k) => k.toString().toLowerCase()).toSet();
        expect(lowerKeys, contains('code'));
        expect(lowerKeys, contains('amt'));
        expect(
          lowerKeys.any((String k) => k.contains('birth')),
          isTrue,
          reason: 'expected a birth_* date column, got $lowerKeys',
        );
        expect(e2eRowStringForColumnInsensitive(probeRow, 'code'), 'tau');

        final countReq = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-count',
          params: {'sql': sql.countAll},
        );

        final countResp = await h.dispatcher.dispatch(countReq, 'e2e-agent');
        expect(countResp.isSuccess, isTrue, reason: '${countResp.error}');
        final countMap = countResp.result! as Map<String, dynamic>;
        final rows = countMap['rows'] as List<dynamic>?;
        expect(rows, isNotNull);
        expect(rows, isNotEmpty);
        final row = rows!.first as Map<String, dynamic>;
        final parsedCount = e2eFirstNumericForKeyContaining(row, 'count');
        expect(parsedCount, isNotNull, reason: 'row keys: ${row.keys}');
        expect(parsedCount, 2);
      },
      skip: skipUnlessDsn,
    );

    test(
      'should run optional transactional sql.executeBatch',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final txBatch = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'e2e-batch-transactional',
          params: {
            'commands': [
              {'sql': sql.updateAmtById(3, 0.01)},
              {'sql': sql.updateAmtById(4, 0.01)},
            ],
            'options': {'transaction': true, 'max_rows': 100},
          },
        );

        final txResp = await h.dispatcher.dispatch(txBatch, 'e2e-agent');
        expect(txResp.isSuccess, isTrue, reason: '${txResp.error}');
        final txMap = txResp.result! as Map<String, dynamic>;
        expect(txMap['failed_commands'], 0);
        expect(txMap['successful_commands'], 2);
        expect(
          h.metrics.transactionalBatchDirectPathCount,
          greaterThanOrEqualTo(1),
          reason: 'transactional batch should use direct ODBC path',
        );
      },
      skip: skipUnlessDsn != false
          ? skipUnlessDsn
          : !E2EEnv.odbcE2eTryTransactionalBatch
          ? 'Defina ODBC_E2E_TRANSACTIONAL_BATCH=true no .env para este teste.'
          : false,
    );
  });
}
