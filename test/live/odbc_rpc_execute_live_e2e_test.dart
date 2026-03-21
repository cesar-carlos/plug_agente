@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

import '../helpers/e2e_env.dart';
import '../helpers/live_test_env.dart';
import '../helpers/odbc_e2e_live_sql.dart';
import '../helpers/odbc_e2e_recording_stream_emitter.dart';
import '../helpers/odbc_e2e_row_assertions.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';
import '../helpers/odbc_e2e_rpc_request_builders.dart';

/// E2E: `sql.execute` (multi-result) and `sql.executeBatch` (SELECT/DML) against
/// real ODBC databases. Covers contract cases from `docs/communication/` (batch
/// DML mix, `execution_order`, `multi_result`). Exercises **product paths** (RPC
/// + gateway), not Dart line coverage (use `flutter test --coverage` for LCOV).
///
/// Runs one nested group per **distinct** DSN among primary, SQL Server, and
/// PostgreSQL when those env vars are set (see [E2EEnv.odbcRpcLiveTargets]).
///
/// DDL uses the gateway `executeNonQuery` because the RPC SQL validator does not
/// allow CREATE/DROP.
///
/// Tests run in **declaration order** within each group.
void main() async {
  await loadLiveTestEnv();

  final targets = E2EEnv.odbcRpcLiveTargets;
  if (targets.isEmpty) {
    group('ODBC RPC live paths (E2E)', () {
      test(
        'skipped — no ODBC DSN configured for RPC live matrix',
        () {},
        skip: E2EEnv.skipReasonOdbcRpcLiveMatrix,
      );
    });
    return;
  }

  for (final target in targets) {
    _registerTargetGroup(target.label, target.dsn);
  }
}

void _registerTargetGroup(String label, String connectionString) {
  group('ODBC RPC live paths (E2E) — $label', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;
    late OdbcE2eLiveSql sql;

    setUpAll(() async {
      final tableName = newOdbcE2eLiveTableName();
      sql = OdbcE2eLiveSql(
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

    test('should insert three rows via sql.executeBatch', () async {
      expect(
        isReady,
        isTrue,
        reason: 'ODBC init failed or DSN not configured',
      );
      final h = harness!;

      final insertBatch = e2eRpcExecuteBatch(
        id: 'e2e-batch-insert',
        commands: <Map<String, dynamic>>[
          <String, dynamic>{
            'sql': sql.insertRow(
              id: 1,
              code: 'alpha',
              amt: 10.5,
              birthDate: '2024-01-10',
              ts: '2024-06-01 12:00:00',
              isActive: true,
            ),
          },
          <String, dynamic>{
            'sql': sql.insertRow(
              id: 2,
              code: 'beta',
              amt: 20,
              birthDate: '2024-02-11',
              ts: '2024-06-02 13:30:00',
              isActive: false,
            ),
          },
          <String, dynamic>{
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
        options: <String, dynamic>{'transaction': false, 'max_rows': 500},
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
    });

    test(
      'should stream rows via sql.execute (ODBC cursor path) when stream '
      'emitter is provided',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final beforeFromDb = h.metrics.rpcSqlExecuteStreamingFromDbResponseCount;
        final emitter = OdbcE2eRecordingRpcStreamEmitter();
        final streamReq = e2eRpcExecute(
          id: 'e2e-stream-from-db',
          sql: sql.selectIdCodeOrderById,
        );

        final streamResp = await h.dispatcher.dispatch(
          streamReq,
          'e2e-agent',
          streamEmitter: emitter,
          limits: const TransportLimits(streamingChunkSize: 1),
        );

        expect(streamResp.isSuccess, isTrue, reason: '${streamResp.error}');
        final body = streamResp.result! as Map<String, dynamic>;
        expect(body['stream_id'], isNotNull);
        expect(body['row_count'], 0);

        expect(emitter.complete, isNotNull);
        expect(emitter.complete!.totalRows, 3);
        expect(emitter.complete!.terminalStatus, isNull);

        expect(
          h.metrics.rpcSqlExecuteStreamingFromDbResponseCount,
          greaterThan(beforeFromDb),
        );

        var streamed = 0;
        for (final chunk in emitter.chunks) {
          streamed += chunk.rows.length;
        }
        expect(streamed, 3);
        expect(emitter.chunks, isNotEmpty);

        final ids = <int>[];
        for (final chunk in emitter.chunks) {
          for (final row in chunk.rows) {
            final idVal = row['id'] ?? row['ID'];
            expect(idVal, isNotNull, reason: 'row keys: ${row.keys}');
            ids.add((idVal as num).toInt());
          }
        }
        ids.sort();
        expect(ids, orderedEquals(<int>[1, 2, 3]));
      },
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

        final selectBatch = e2eRpcExecuteBatch(
          id: 'e2e-batch-select',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{'sql': sql.selectIdCodeAmtById(1)},
            <String, dynamic>{'sql': sql.selectIdCodeAmtById(2)},
            <String, dynamic>{'sql': sql.countAll},
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 100},
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
    );

    test(
      'should paginate sql.execute with ORDER BY (page / page_size)',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final page1Req = e2eRpcExecute(
          id: 'e2e-page-1',
          sql: sql.selectIdCodeOrderById,
          options: <String, dynamic>{'page': 1, 'page_size': 2},
        );
        final page1Resp = await h.dispatcher.dispatch(page1Req, 'e2e-agent');
        expect(page1Resp.isSuccess, isTrue, reason: '${page1Resp.error}');
        final map1 = page1Resp.result! as Map<String, dynamic>;
        expect(map1['row_count'], 2);
        final pag1 = map1['pagination'] as Map<String, dynamic>?;
        expect(pag1, isNotNull);
        expect(pag1!['has_next_page'], isTrue);
        expect(pag1['has_previous_page'], isFalse);

        final page2Req = e2eRpcExecute(
          id: 'e2e-page-2',
          sql: sql.selectIdCodeOrderById,
          options: <String, dynamic>{'page': 2, 'page_size': 2},
        );
        final page2Resp = await h.dispatcher.dispatch(page2Req, 'e2e-agent');
        expect(page2Resp.isSuccess, isTrue, reason: '${page2Resp.error}');
        final map2 = page2Resp.result! as Map<String, dynamic>;
        expect(map2['row_count'], 1);
        final pag2 = map2['pagination'] as Map<String, dynamic>?;
        expect(pag2, isNotNull);
        expect(pag2!['has_next_page'], isFalse);
        expect(pag2['has_previous_page'], isTrue);
      },
    );

    test(
      'should stream materialized sql.execute in chunks when DB streaming is '
      'off and row threshold is low',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;
        when(
          () => h.featureFlags.enableSocketStreamingFromDb,
        ).thenReturn(false);
        addTearDown(() {
          when(
            () => h.featureFlags.enableSocketStreamingFromDb,
          ).thenReturn(true);
        });

        final beforeChunks = h.metrics.rpcSqlExecuteStreamingChunksResponseCount;
        final emitter = OdbcE2eRecordingRpcStreamEmitter();
        final resp = await h.dispatcher.dispatch(
          e2eRpcExecute(
            id: 'e2e-mem-stream',
            sql: sql.selectIdCodeOrderById,
          ),
          'e2e-agent',
          streamEmitter: emitter,
          limits: const TransportLimits(
            streamingRowThreshold: 1,
            streamingChunkSize: 1,
          ),
        );

        expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        final body = resp.result! as Map<String, dynamic>;
        expect(body['stream_id'], isNotNull);
        expect(body['row_count'], 0);
        expect(emitter.complete, isNotNull);
        expect(emitter.complete!.totalRows, 3);
        expect(emitter.complete!.terminalStatus, isNull);
        expect(
          h.metrics.rpcSqlExecuteStreamingChunksResponseCount,
          greaterThan(beforeChunks),
        );
        var streamed = 0;
        for (final chunk in emitter.chunks) {
          streamed += chunk.rows.length;
        }
        expect(streamed, 3);
      },
    );

    test(
      'should cancel in-flight sql.execute DB stream via sql.cancel',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;
        final longSql = E2EEnv.odbcLongQueryForDsn(connectionString)!;
        const executeRpcId = 'e2e-cancel-stream';
        final emitter = OdbcE2eRecordingRpcStreamEmitter();
        final execFuture = h.dispatcher.dispatch(
          e2eRpcExecute(id: executeRpcId, sql: longSql),
          'e2e-agent',
          streamEmitter: emitter,
          limits: const TransportLimits(streamingChunkSize: 50),
        );

        await Future<void>.delayed(const Duration(milliseconds: 300));
        final cancelResp = await h.dispatcher.dispatch(
          e2eRpcCancel(
            id: 'e2e-cancel-rpc',
            requestId: executeRpcId,
          ),
          'e2e-agent',
        );
        expect(cancelResp.isSuccess, isTrue, reason: '${cancelResp.error}');
        final cancelBody = cancelResp.result! as Map<String, dynamic>;
        expect(cancelBody['cancelled'], isTrue);

        final execResp = await execFuture.timeout(const Duration(seconds: 45));
        expect(
          execResp.isError,
          isTrue,
          reason: 'expected execute error after cancel',
        );
      },
      skip: E2EEnv.skipUnless(
        (() {
          final q = E2EEnv.odbcLongQueryForDsn(connectionString);
          return q != null && q.trim().isNotEmpty;
        })(),
        E2EEnv.skipReasonOdbcLongQueryForTarget,
      ),
    );

    test(
      'should run sql.executeBatch combining insert, update, delete and select',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final combined = e2eRpcExecuteBatch(
          id: 'e2e-batch-combined-dml',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 10,
                code: 'ten',
                amt: 1,
                birthDate: '2024-05-01',
                ts: '2024-06-05 10:00:00',
                isActive: true,
              ),
            },
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 11,
                code: 'eleven',
                amt: 2,
                birthDate: '2024-05-02',
                ts: '2024-06-05 11:00:00',
                isActive: false,
              ),
            },
            <String, dynamic>{'sql': sql.updateCodeById(10, 'ten-updated')},
            <String, dynamic>{'sql': sql.deleteById(11)},
            <String, dynamic>{'sql': sql.selectIdCodeAmtById(10)},
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 100},
        );

        final resp = await h.dispatcher.dispatch(combined, 'e2e-agent');
        expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        final map = resp.result! as Map<String, dynamic>;
        expect(map['failed_commands'], 0);
        expect(map['successful_commands'], 5);
        final items = map['items'] as List<dynamic>;
        expect(items, hasLength(5));
        for (var i = 0; i < 4; i++) {
          final item = items[i] as Map<String, dynamic>;
          expect(item['ok'], isTrue, reason: 'item $i: $item');
        }
        final selectItem = items[4] as Map<String, dynamic>;
        expect(selectItem['ok'], isTrue);
        final rows = selectItem['rows'] as List<dynamic>?;
        expect(rows, isNotNull);
        expect(rows, hasLength(1));
        final row = rows!.first as Map<String, dynamic>;
        expect(e2eRowStringForColumnInsensitive(row, 'code'), 'ten-updated');
      },
    );

    test(
      'should honor sql.executeBatch execution_order (ordered steps before '
      'list order)',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final orderBatch = e2eRpcExecuteBatch(
          id: 'e2e-batch-exec-order',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{
              'sql': sql.setAmtById(1, 100),
              'execution_order': 2,
            },
            <String, dynamic>{
              'sql': sql.multiplyAmtById(1, 10),
              'execution_order': 1,
            },
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 50},
        );

        final batchResp = await h.dispatcher.dispatch(
          orderBatch,
          'e2e-agent',
        );
        expect(batchResp.isSuccess, isTrue, reason: '${batchResp.error}');
        final batchMap = batchResp.result! as Map<String, dynamic>;
        expect(batchMap['failed_commands'], 0);
        expect(batchMap['successful_commands'], 2);

        final probe = e2eRpcExecute(
          id: 'e2e-amt-probe',
          sql: sql.selectIdCodeAmtById(1),
        );
        final probeResp = await h.dispatcher.dispatch(probe, 'e2e-agent');
        expect(probeResp.isSuccess, isTrue, reason: '${probeResp.error}');
        final probeRows = (probeResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
        expect(probeRows, isNotNull);
        expect(probeRows, hasLength(1));
        final amt = e2eFirstNumericForKeyContaining(
          probeRows!.first as Map<String, dynamic>,
          'amt',
        );
        expect(amt, isNotNull);
        expect(amt, closeTo(100.0, 0.01));
      },
    );

    test(
      'should run ordered commands before unordered ones in sql.executeBatch',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final batch = e2eRpcExecuteBatch(
          id: 'e2e-batch-mixed-order',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 12,
                code: 'twelve',
                amt: 12,
                birthDate: '2024-05-10',
                ts: '2024-06-06 12:00:00',
                isActive: true,
              ),
            },
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 14,
                code: 'fourteen',
                amt: 14,
                birthDate: '2024-05-12',
                ts: '2024-06-06 14:00:00',
                isActive: false,
              ),
              'execution_order': 1,
            },
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 13,
                code: 'thirteen',
                amt: 13,
                birthDate: '2024-05-11',
                ts: '2024-06-06 13:00:00',
                isActive: true,
              ),
              'execution_order': 2,
            },
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 50},
        );

        final resp = await h.dispatcher.dispatch(batch, 'e2e-agent');
        expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        final map = resp.result! as Map<String, dynamic>;
        expect(map['failed_commands'], 0);
        expect(map['successful_commands'], 3);
        final items = map['items'] as List<dynamic>;
        expect(items, hasLength(3));
        for (final dynamic raw in items) {
          final item = raw as Map<String, dynamic>;
          expect(item['ok'], isTrue, reason: '$item');
        }

        final verify = e2eRpcExecute(
          id: 'e2e-verify-12-14',
          sql: 'SELECT id FROM ${sql.tableName} WHERE id IN (12, 13, 14) ORDER BY id',
        );
        final vResp = await h.dispatcher.dispatch(verify, 'e2e-agent');
        expect(vResp.isSuccess, isTrue, reason: '${vResp.error}');
        final vRows = (vResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
        expect(vRows, isNotNull);
        expect(vRows, hasLength(3));
      },
    );

    test(
      'should bind sql.execute params (rpc.params.sql-execute / ODBC named)',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final namedReq = e2eRpcExecuteWithParams(
          id: 'e2e-sql-execute-named',
          sql: sql.selectCodeWhereIdNamed('rid'),
          boundParams: <String, dynamic>{'rid': 2},
        );
        final namedResp = await h.dispatcher.dispatch(
          namedReq,
          'e2e-agent',
        );
        expect(namedResp.isSuccess, isTrue, reason: '${namedResp.error}');
        final rows = (namedResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
        expect(rows, isNotNull);
        expect(rows, hasLength(1));
        expect(
          e2eRowStringForColumnInsensitive(
            rows!.first as Map<String, dynamic>,
            'code',
          ),
          'beta',
        );
      },
    );

    test(
      'should bind commands[].params in sql.executeBatch '
      '(rpc.params.sql-execute-batch)',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final batch = e2eRpcExecuteBatch(
          id: 'e2e-batch-per-command-params',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{
              'sql': sql.updateCodeWhereIdNamed('new_code', 'row_id'),
              'params': <String, dynamic>{
                'new_code': 'e2e-batch-bound',
                'row_id': 2,
              },
            },
            <String, dynamic>{
              'sql': sql.selectCodeWhereIdNamed('qid'),
              'params': <String, dynamic>{'qid': 2},
            },
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 50},
        );

        final resp = await h.dispatcher.dispatch(batch, 'e2e-agent');
        expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        final map = resp.result! as Map<String, dynamic>;
        expect(map['failed_commands'], 0);
        expect(map['successful_commands'], 2);
        final items = map['items'] as List<dynamic>;
        expect(items, hasLength(2));
        final selectItem = items[1] as Map<String, dynamic>;
        expect(selectItem['ok'], isTrue);
        final sRows = selectItem['rows'] as List<dynamic>?;
        expect(sRows, isNotNull);
        expect(sRows, hasLength(1));
        expect(
          e2eRowStringForColumnInsensitive(
            sRows!.first as Map<String, dynamic>,
            'code',
          ),
          'e2e-batch-bound',
        );
      },
    );

    test(
      'should return error and roll back transactional sql.executeBatch when '
      'a command fails (atomicidade)',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        final badTx = e2eRpcExecuteBatch(
          id: 'e2e-batch-tx-rollback',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{'sql': sql.updateCodeById(3, 'tx-will-rollback')},
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 1,
                code: 'dup-pk',
                amt: 0,
                birthDate: '2024-01-01',
                ts: '2024-01-01 00:00:00',
                isActive: false,
              ),
            },
          ],
          options: <String, dynamic>{'transaction': true, 'max_rows': 50},
        );

        final txResp = await h.dispatcher.dispatch(badTx, 'e2e-agent');
        expect(txResp.isError, isTrue, reason: 'expected batch failure');

        final probe = e2eRpcExecute(
          id: 'e2e-after-tx-fail',
          sql: sql.selectIdCodeAmtById(3),
        );
        final probeResp = await h.dispatcher.dispatch(probe, 'e2e-agent');
        expect(probeResp.isSuccess, isTrue, reason: '${probeResp.error}');
        final pRows = (probeResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
        expect(pRows, isNotNull);
        expect(pRows, hasLength(1));
        expect(
          e2eRowStringForColumnInsensitive(
            pRows!.first as Map<String, dynamic>,
            'code',
          ),
          'gamma',
        );
      },
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

        final scrub = await h.gateway.executeNonQuery(
          'DELETE FROM ${sql.tableName} WHERE id IN (10, 12, 13, 14)',
          null,
        );
        expect(scrub.isSuccess(), isTrue, reason: '$scrub');

        final multi = e2eRpcExecute(
          id: 'e2e-multi-result',
          sql: sql.multiResultProbe,
          options: <String, dynamic>{'multi_result': true, 'max_rows': 100},
        );

        final multiResp = await h.dispatcher.dispatch(multi, 'e2e-agent');
        expect(multiResp.isSuccess, isTrue, reason: '${multiResp.error}');
        final multiMap = multiResp.result! as Map<String, dynamic>;
        expect(multiMap['multi_result'], isTrue);
        final sets = multiMap['result_sets'] as List<dynamic>? ?? <dynamic>[];
        final multiRows = multiMap['rows'] as List<dynamic>? ?? <dynamic>[];
        if (sets.isEmpty && multiRows.isEmpty) {
          if (E2EEnv.odbcE2eRequireMultiResult) {
            fail(
              'ODBC_E2E_REQUIRE_MULTI_RESULT=true but sql.execute with '
              'multi_result returned no result_sets/rows. The gateway normally '
              'retries multi-result on a direct connection when the pool returns '
              'an empty payload; if this still fails, check driver/odbc_fast.',
            );
          }
          final pickOne = e2eRpcExecute(
            id: 'e2e-fallback-row',
            sql: 'SELECT id, code, amt FROM ${sql.tableName} WHERE id = 1',
          );
          final pickResp = await h.dispatcher.dispatch(pickOne, 'e2e-agent');
          expect(pickResp.isSuccess, isTrue, reason: '${pickResp.error}');
          final pickRows = (pickResp.result! as Map<String, dynamic>)['rows'] as List<dynamic>?;
          expect(pickRows, isNotNull);
          expect(pickRows, isNotEmpty);

          final pickCount = e2eRpcExecute(
            id: 'e2e-fallback-count',
            sql: 'SELECT COUNT(*) AS row_count FROM ${sql.tableName}',
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

        final updateBatch = e2eRpcExecuteBatch(
          id: 'e2e-batch-update',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{'sql': sql.updateAmtById(1, 1)},
            <String, dynamic>{'sql': sql.updateCodeById(2, 'patched')},
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 100},
        );

        final updateResp = await h.dispatcher.dispatch(
          updateBatch,
          'e2e-agent',
        );
        expect(updateResp.isSuccess, isTrue, reason: '${updateResp.error}');
        final updateMap = updateResp.result! as Map<String, dynamic>;
        expect(updateMap['failed_commands'], 0);
        expect(updateMap['successful_commands'], 2);

        final mixedBatch = e2eRpcExecuteBatch(
          id: 'e2e-batch-mixed',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{
              'sql': sql.insertRow(
                id: 4,
                code: 'delta',
                amt: 40,
                birthDate: '2024-04-13',
                ts: '2024-06-04 15:00:00',
                isActive: false,
              ),
            },
            <String, dynamic>{'sql': sql.updateCodeById(3, 'tau')},
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 100},
        );

        final mixedResp = await h.dispatcher.dispatch(
          mixedBatch,
          'e2e-agent',
        );
        expect(mixedResp.isSuccess, isTrue, reason: '${mixedResp.error}');
        final mixedMap = mixedResp.result! as Map<String, dynamic>;
        expect(mixedMap['failed_commands'], 0);
        expect(mixedMap['successful_commands'], 2);

        final deleteBatch = e2eRpcExecuteBatch(
          id: 'e2e-batch-delete',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{'sql': sql.deleteById(1)},
            <String, dynamic>{'sql': sql.deleteById(2)},
          ],
          options: <String, dynamic>{'transaction': false, 'max_rows': 50},
        );

        final deleteResp = await h.dispatcher.dispatch(
          deleteBatch,
          'e2e-agent',
        );
        expect(deleteResp.isSuccess, isTrue, reason: '${deleteResp.error}');
        final deleteMap = deleteResp.result! as Map<String, dynamic>;
        expect(deleteMap['failed_commands'], 0);
        expect(deleteMap['successful_commands'], 2);

        final rowProbe = e2eRpcExecute(
          id: 'e2e-row-probe',
          sql: 'SELECT * FROM ${sql.tableName} WHERE id = 3',
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

        final countReq = e2eRpcExecute(
          id: 'e2e-count',
          sql: sql.countAll,
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

        final txBatch = e2eRpcExecuteBatch(
          id: 'e2e-batch-transactional',
          commands: <Map<String, dynamic>>[
            <String, dynamic>{'sql': sql.updateAmtById(3, 0.01)},
            <String, dynamic>{'sql': sql.updateAmtById(4, 0.01)},
          ],
          options: <String, dynamic>{'transaction': true, 'max_rows': 100},
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
      skip: E2EEnv.skipUnless(
        E2EEnv.odbcE2eTryTransactionalBatch,
        E2EEnv.skipReasonOdbcTransactionalBatch,
      ),
    );
  });
}
