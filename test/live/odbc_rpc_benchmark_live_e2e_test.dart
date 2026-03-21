@Tags(['live', 'benchmark'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:uuid/uuid.dart';

import '../helpers/e2e_benchmark_assertions.dart';
import '../helpers/e2e_benchmark_recorder.dart';
import '../helpers/e2e_env.dart';
import '../helpers/live_test_env.dart';
import '../helpers/odbc_e2e_live_sql.dart';
import '../helpers/odbc_e2e_recording_stream_emitter.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';
import '../helpers/odbc_e2e_rpc_request_builders.dart';

/// E2E benchmarks for ODBC-backed `sql.execute` / `sql.executeBatch` through
/// the real RPC dispatcher. Opt-in with `ODBC_E2E_BENCHMARK=true`.
///
/// When `ODBC_E2E_BENCHMARK_RECORD=true`, appends one JSON object per line
/// (JSONL) to [E2EEnv.odbcE2eBenchmarkRecordFile] for local trend tracking.
void main() async {
  await loadLiveTestEnv();

  if (!E2EEnv.odbcE2eBenchmarkEnabled) {
    group('ODBC RPC benchmark (E2E)', () {
      test(
        'skipped — enable ODBC_E2E_BENCHMARK=true to run',
        () {},
        skip: E2EEnv.skipReasonOdbcE2eBenchmark,
      );
    });
    return;
  }

  final targets = E2EEnv.odbcRpcLiveTargets;
  if (targets.isEmpty) {
    group('ODBC RPC benchmark (E2E)', () {
      test(
        'skipped — no ODBC DSN configured',
        () {},
        skip: E2EEnv.skipReasonOdbcRpcLiveMatrix,
      );
    });
    return;
  }

  final runId = const Uuid().v4();
  for (final target in targets) {
    _registerBenchmarkGroup(target.label, target.dsn, runId: runId);
  }
}

String _e2eFlutterBenchmarkBuildMode() {
  if (kReleaseMode) {
    return 'release';
  }
  if (kProfileMode) {
    return 'profile';
  }
  return 'debug';
}

Map<String, int> _metricsSnapshot(MetricsCollector m) => <String, int>{
  'rpc_sql_execute_materialized_response': m.rpcSqlExecuteMaterializedResponseCount,
  'rpc_sql_execute_streaming_from_db_response': m.rpcSqlExecuteStreamingFromDbResponseCount,
  'rpc_sql_execute_streaming_chunks_response': m.rpcSqlExecuteStreamingChunksResponseCount,
  'multi_result_pool_vacuous_fallback': m.multiResultPoolVacuousFallbackCount,
  'multi_result_direct_still_vacuous': m.multiResultDirectStillVacuousCount,
  'transactional_batch_direct_path': m.transactionalBatchDirectPathCount,
};

bool _multiResultHasPayload(Map<String, dynamic> body) {
  final sets = body['result_sets'] as List<dynamic>? ?? <dynamic>[];
  final rows = body['rows'] as List<dynamic>? ?? <dynamic>[];
  return sets.isNotEmpty || rows.isNotEmpty;
}

void _registerBenchmarkGroup(
  String label,
  String connectionString, {
  required String runId,
}) {
  group('ODBC RPC benchmark (E2E) — $label', () {
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

      final seed = e2eRpcExecuteBatch(
        id: 'bench-seed',
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
      final seedResp = await opened.dispatcher.dispatch(seed, 'e2e-agent');
      expect(seedResp.isSuccess, isTrue, reason: '${seedResp.error}');

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
      'should measure rpc sql.execute / executeBatch and optionally append '
      'JSONL history',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;

        var seq = 0;
        String benchId(String kind) => 'bench-$kind-${seq++}';

        final materialized = await E2eBenchmarkStats.measureAsync(() async {
          final resp = await h.dispatcher.dispatch(
            e2eRpcExecute(
              id: benchId('mat'),
              sql: sql.selectIdCodeOrderById,
            ),
            'e2e-agent',
          );
          expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        });

        final batchReads = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecuteBatch(
                id: benchId('batch'),
                commands: <Map<String, dynamic>>[
                  <String, dynamic>{'sql': sql.selectIdCodeAmtById(1)},
                  <String, dynamic>{'sql': sql.selectIdCodeAmtById(2)},
                  <String, dynamic>{'sql': sql.countAll},
                ],
                options: <String, dynamic>{
                  'transaction': false,
                  'max_rows': 100,
                },
              ),
              'e2e-agent',
            );
            expect(resp.isSuccess, isTrue, reason: '${resp.error}');
          },
          warmup: 1,
          iterations: 6,
        );

        final namedParams = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecuteWithParams(
                id: benchId('named'),
                sql: sql.selectCodeWhereIdNamed('rid'),
                boundParams: <String, dynamic>{'rid': 2},
              ),
              'e2e-agent',
            );
            expect(resp.isSuccess, isTrue, reason: '${resp.error}');
          },
          warmup: 1,
          iterations: 6,
        );

        var lastMultiHasPayload = false;
        final multiStats = await E2eBenchmarkStats.measureAsync(
          () async {
            final multiResp = await h.dispatcher.dispatch(
              e2eRpcExecute(
                id: benchId('multi'),
                sql: sql.multiResultProbe,
                options: <String, dynamic>{
                  'multi_result': true,
                  'max_rows': 100,
                },
              ),
              'e2e-agent',
            );
            expect(multiResp.isSuccess, isTrue, reason: '${multiResp.error}');
            final multiMap = multiResp.result! as Map<String, dynamic>;
            lastMultiHasPayload = _multiResultHasPayload(multiMap);
          },
          warmup: 1,
          iterations: 3,
        );

        final batchTx = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecuteBatch(
                id: benchId('btx'),
                commands: <Map<String, dynamic>>[
                  <String, dynamic>{'sql': sql.setAmtById(1, 10.5)},
                  <String, dynamic>{'sql': sql.selectIdCodeAmtById(1)},
                ],
                options: <String, dynamic>{
                  'transaction': true,
                  'max_rows': 50,
                },
              ),
              'e2e-agent',
            );
            expect(resp.isSuccess, isTrue, reason: '${resp.error}');
          },
          warmup: 1,
          iterations: 4,
        );

        final streaming = await E2eBenchmarkStats.measureAsync(
          () async {
            final emitter = OdbcE2eRecordingRpcStreamEmitter();
            final streamResp = await h.dispatcher.dispatch(
              e2eRpcExecute(
                id: benchId('stream'),
                sql: sql.selectIdCodeOrderById,
              ),
              'e2e-agent',
              streamEmitter: emitter,
              limits: const TransportLimits(streamingChunkSize: 1),
            );
            expect(streamResp.isSuccess, isTrue, reason: '${streamResp.error}');
            expect(emitter.complete, isNotNull);
            expect(emitter.complete!.totalRows, 3);
          },
          warmup: 1,
          iterations: 4,
        );

        final cases = <String, dynamic>{
          'rpc_sql_execute_materialized': materialized.toJson(),
          'rpc_sql_execute_batch_reads': batchReads.toJson(),
          'rpc_sql_execute_named_params': namedParams.toJson(),
          'rpc_sql_execute_multi_result': <String, dynamic>{
            ...multiStats.toJson(),
            'last_has_payload': lastMultiHasPayload,
          },
          'rpc_sql_execute_batch_tx': batchTx.toJson(),
          'rpc_sql_execute_streaming': streaming.toJson(),
        };

        if (E2EEnv.odbcE2eRequireMultiResult) {
          expect(
            lastMultiHasPayload,
            isTrue,
            reason:
                'multi_result probe returned no result_sets/rows; '
                'driver may not support multi-result, or ODBC_E2E_REQUIRE_MULTI_RESULT '
                'should stay false for this target',
          );
        }

        final caps = E2EEnv.odbcE2eBenchmarkMaxMsByCase;
        if (caps.isNotEmpty) {
          assertE2eBenchmarkWithinThresholds(cases: cases, thresholds: caps);
        }

        if (E2EEnv.odbcE2eBenchmarkRecordEnabled) {
          final out = resolveE2eBenchmarkOutputFile(
            E2EEnv.odbcE2eBenchmarkRecordFile,
          );
          final hosting = E2EEnv.odbcE2eBenchmarkDbHosting;
          appendE2eBenchmarkRecord(
            file: out,
            record: <String, dynamic>{
              'schema_version': 2,
              'suite': 'odbc_rpc_benchmark',
              'run_id': runId,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
              'target_label': label,
              'build_mode': _e2eFlutterBenchmarkBuildMode(),
              'database_hosting': ?hosting,
              'git_revision': resolveE2eGitRevision(),
              'dart_platform': Platform.operatingSystem,
              'dart_version': Platform.version.split('\n').first,
              'metrics_counters': _metricsSnapshot(h.metrics),
              'cases': cases,
            },
          );
        }
      },
    );
  });
}
