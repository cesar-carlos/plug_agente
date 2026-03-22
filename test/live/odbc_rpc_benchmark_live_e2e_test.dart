@Tags(['live', 'benchmark'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:uuid/uuid.dart';

import '../../tool/e2e_benchmark_profile_parse.dart';
import '../../tool/e2e_benchmark_summary.dart';
import '../helpers/e2e_benchmark_assertions.dart';
import '../helpers/e2e_benchmark_recorder.dart';
import '../helpers/e2e_env.dart';
import '../helpers/live_test_env.dart';
import '../helpers/mock_odbc_connection_settings.dart';
import '../helpers/odbc_e2e_live_sql.dart';
import '../helpers/odbc_e2e_recording_stream_emitter.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';
import '../helpers/odbc_e2e_rpc_request_builders.dart';

const String _caseMaterialized = 'rpc_sql_execute_materialized';
const String _caseBatchReads = 'rpc_sql_execute_batch_reads';
const String _caseNamedParams = 'rpc_sql_execute_named_params';
const String _caseMultiResult = 'rpc_sql_execute_multi_result';
const String _caseBatchTx = 'rpc_sql_execute_batch_tx';
const String _caseWriteDml = 'rpc_sql_execute_write_dml';
const String _caseWriteDmlParallel = 'rpc_sql_execute_write_dml_parallel';
const String _caseTimeoutCancel = 'rpc_sql_execute_timeout_cancel';
const String _caseStreamingDb = 'rpc_sql_execute_streaming';
const String _caseStreamingChunks = 'rpc_sql_execute_streaming_chunks';
const String _caseMaterializedParallel = 'rpc_sql_execute_materialized_parallel';
const String _caseBatchReadsParallel = 'rpc_sql_execute_batch_reads_parallel';
const String _caseMultiResultParallel = 'rpc_sql_execute_multi_result_parallel';

class _StreamingIterationMeasurement {
  const _StreamingIterationMeasurement({
    required this.firstChunkLatencyMs,
    required this.chunkCount,
    required this.totalRows,
  });

  final int firstChunkLatencyMs;
  final int chunkCount;
  final int totalRows;
}

class _StreamingCaseMeasurement {
  const _StreamingCaseMeasurement({
    required this.stats,
    required this.firstChunkLatencySamplesMs,
    required this.chunkCountSamples,
    required this.totalRowsSamples,
  });

  final E2eBenchmarkStats stats;
  final List<int> firstChunkLatencySamplesMs;
  final List<int> chunkCountSamples;
  final List<int> totalRowsSamples;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...stats.toJson(),
      'first_chunk_latency_median_ms': _medianInt(firstChunkLatencySamplesMs),
      'first_chunk_latency_samples_ms': List<int>.from(
        firstChunkLatencySamplesMs,
      ),
      'chunk_count_median': _medianInt(chunkCountSamples),
      'chunk_count_samples': List<int>.from(chunkCountSamples),
      'total_rows_median': _medianInt(totalRowsSamples),
      'total_rows_samples': List<int>.from(totalRowsSamples),
    };
  }
}

int _medianInt(List<int> samples) {
  if (samples.isEmpty) {
    return 0;
  }
  final sorted = List<int>.from(samples)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

MockOdbcConnectionSettings _benchmarkSettings(
  OdbcE2eBenchmarkProfile profile,
) {
  return MockOdbcConnectionSettings(
    poolSize: profile.poolSize,
    loginTimeoutSeconds: E2EEnv.odbcE2eBenchmarkLoginTimeoutSeconds,
    maxResultBufferMb: E2EEnv.odbcE2eBenchmarkMaxResultBufferMb,
    streamingChunkSizeKb: E2EEnv.odbcE2eBenchmarkStreamingChunkSizeKb,
    useNativeOdbcPool: profile.poolMode == 'native',
  );
}

Map<String, dynamic> _benchmarkProfile(
  OdbcE2eBenchmarkProfile profile,
  MockOdbcConnectionSettings settings,
) {
  return <String, dynamic>{
    'profile_key': profile.key,
    'pool_mode': settings.useNativeOdbcPool ? 'native' : 'lease',
    'pool_size': settings.poolSize,
    'concurrency': profile.concurrency,
    'seed_rows': E2EEnv.odbcE2eBenchmarkSeedRows,
    'login_timeout_seconds': settings.loginTimeoutSeconds,
    'max_result_buffer_mb': settings.maxResultBufferMb,
    'streaming_chunk_size_kb': settings.streamingChunkSizeKb,
  };
}

List<SqlCommand> _seedCommands(
  OdbcE2eLiveSql sql,
  int rowCount,
) {
  return List<SqlCommand>.generate(rowCount, (int index) {
    final id = index + 1;
    final day = (((id - 1) % 28) + 1).toString().padLeft(2, '0');
    final hour = ((id - 1) % 24).toString().padLeft(2, '0');
    return SqlCommand(
      sql: sql.insertRow(
        id: id,
        code: 'code_$id',
        amt: 10 + (id / 10),
        birthDate: '2024-01-$day',
        ts: '2024-06-$day $hour:00:00',
        isActive: id.isEven,
      ),
    );
  });
}

List<Map<String, dynamic>> _batchReadCommands(
  OdbcE2eLiveSql sql,
  int rowCount,
) {
  final splitId = (rowCount / 2).ceil();
  return <Map<String, dynamic>>[
    <String, dynamic>{'sql': sql.selectIdCodeAmtUpToId(splitId)},
    <String, dynamic>{'sql': sql.selectIdCodeAmtFromId(splitId + 1)},
    <String, dynamic>{'sql': sql.countAll},
  ];
}

String _multiResultSql(
  OdbcE2eLiveSql sql,
  int rowCount,
) {
  final splitId = (rowCount / 2).ceil();
  return sql.multiResultBenchmarkProbe(splitId);
}

List<Map<String, dynamic>> _writeDmlCommands(
  OdbcE2eLiveSql sql, {
  required int tempId,
}) {
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'sql': sql.insertRow(
        id: tempId,
        code: 'bench_$tempId',
        amt: 11.5,
        birthDate: '2024-01-01',
        ts: '2024-06-01 00:00:00',
        isActive: true,
      ),
    },
    <String, dynamic>{'sql': sql.updateAmtById(tempId, 1.25)},
    <String, dynamic>{'sql': sql.deleteById(tempId)},
  ];
}

String _timeoutProbeSql(OdbcE2eLiveSql sql) =>
    'SELECT a.id AS a_id, b.id AS b_id, c.id AS c_id '
    'FROM ${sql.tableName} a, ${sql.tableName} b, ${sql.tableName} c';

bool _requireTimeoutCancelFailure() => E2EEnv.odbcE2eBenchmarkRequireTimeoutCancel;

Map<String, dynamic> _statsWithConcurrency(
  E2eBenchmarkStats stats, {
  required int concurrency,
}) {
  return <String, dynamic>{
    ...stats.toJson(),
    'concurrency': concurrency,
    'operations_per_iteration': concurrency,
  };
}

List<Map<String, dynamic>> _loadBaselineRecords(String configuredPath) {
  final file = resolveE2eBenchmarkOutputFile(configuredPath);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'Benchmark baseline file not found: ${file.path}. '
        'Disable baseline regression env vars or record a baseline first.',
  );
  final lines = file.readAsLinesSync().where((String line) {
    return line.trim().isNotEmpty;
  });
  return parseE2eBenchmarkJsonlLines(lines);
}

Future<E2eBenchmarkStats> _measureConcurrentAsync(
  Future<void> Function(int invocation) body, {
  required int concurrency,
  int warmup = 1,
  int iterations = 4,
}) {
  return E2eBenchmarkStats.measureAsync(
    () async {
      await Future.wait(
        List<Future<void>>.generate(concurrency, body),
      );
    },
    warmup: warmup,
    iterations: iterations,
  );
}

Future<_StreamingCaseMeasurement> _measureStreamingCaseAsync(
  Future<_StreamingIterationMeasurement> Function() body, {
  int warmup = 1,
  int iterations = 4,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }

  final elapsedSamples = <int>[];
  final firstChunkLatencySamples = <int>[];
  final chunkCountSamples = <int>[];
  final totalRowsSamples = <int>[];

  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    final measurement = await body();
    stopwatch.stop();
    elapsedSamples.add(stopwatch.elapsedMilliseconds);
    firstChunkLatencySamples.add(measurement.firstChunkLatencyMs);
    chunkCountSamples.add(measurement.chunkCount);
    totalRowsSamples.add(measurement.totalRows);
  }

  return _StreamingCaseMeasurement(
    stats: E2eBenchmarkStats(
      warmup: warmup,
      iterations: iterations,
      samplesMs: elapsedSamples,
    ),
    firstChunkLatencySamplesMs: firstChunkLatencySamples,
    chunkCountSamples: chunkCountSamples,
    totalRowsSamples: totalRowsSamples,
  );
}

/// E2E benchmarks for ODBC-backed `sql.execute` / `sql.executeBatch` through
/// the real RPC dispatcher. Opt-in with `ODBC_E2E_BENCHMARK=true`.
///
/// When `ODBC_E2E_BENCHMARK_RECORD=true`, appends one JSON object per line
/// (JSONL) to [E2EEnv.odbcE2eBenchmarkRecordFile] for local trend tracking.
void main() async {
  await loadLiveTestEnv();
  tearDownAll(() async {
    await OdbcE2eRpcHarness.shutdownSharedLocator();
  });

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

  final profiles = E2EEnv.odbcE2eBenchmarkProfiles;
  final runId = const Uuid().v4();
  for (final target in targets) {
    for (final profile in profiles) {
      _registerBenchmarkGroup(
        target.label,
        target.dsn,
        runId: runId,
        profile: profile,
      );
    }
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

class _LatencySampleOffsets {
  const _LatencySampleOffsets({
    required this.poolAcquire,
    required this.poolRelease,
    required this.poolWait,
    required this.directConnect,
    required this.directDisconnect,
  });

  final int poolAcquire;
  final int poolRelease;
  final int poolWait;
  final int directConnect;
  final int directDisconnect;
}

Map<String, int> _metricsSnapshot(MetricsCollector m) => <String, int>{
  'rpc_sql_execute_materialized_response': m.rpcSqlExecuteMaterializedResponseCount,
  'rpc_sql_execute_streaming_from_db_response': m.rpcSqlExecuteStreamingFromDbResponseCount,
  'rpc_sql_execute_streaming_chunks_response': m.rpcSqlExecuteStreamingChunksResponseCount,
  'multi_result_pool_vacuous_fallback': m.multiResultPoolVacuousFallbackCount,
  'multi_result_direct_still_vacuous': m.multiResultDirectStillVacuousCount,
  'transactional_batch_direct_path': m.transactionalBatchDirectPathCount,
  'connection_pool_acquire_failure': m.connectionPoolAcquireFailureCount,
  'connection_pool_release_failure': m.connectionPoolReleaseFailureCount,
  'connection_pool_acquire_latency_ms_total': m.connectionPoolAcquireLatencyMsTotal,
  'connection_pool_acquire_latency_samples': m.connectionPoolAcquireLatencySamples,
  'connection_pool_release_latency_ms_total': m.connectionPoolReleaseLatencyMsTotal,
  'connection_pool_release_latency_samples': m.connectionPoolReleaseLatencySamples,
  'connection_pool_wait_latency_ms_total': m.connectionPoolWaitLatencyMsTotal,
  'connection_pool_wait_latency_samples': m.connectionPoolWaitLatencySamples,
  'connection_pool_active_peak': m.connectionPoolActivePeak,
  'connection_pool_waiters_peak': m.connectionPoolWaitersPeak,
  'connection_direct_connect_latency_ms_total': m.connectionDirectConnectLatencyMsTotal,
  'connection_direct_connect_latency_samples': m.connectionDirectConnectLatencySamples,
  'connection_direct_disconnect_latency_ms_total': m.connectionDirectDisconnectLatencyMsTotal,
  'connection_direct_disconnect_latency_samples': m.connectionDirectDisconnectLatencySamples,
};

_LatencySampleOffsets _latencySampleOffsetsSnapshot(MetricsCollector m) {
  return _LatencySampleOffsets(
    poolAcquire: m.connectionPoolAcquireLatencySamplesMs.length,
    poolRelease: m.connectionPoolReleaseLatencySamplesMs.length,
    poolWait: m.connectionPoolWaitLatencySamplesMs.length,
    directConnect: m.connectionDirectConnectLatencySamplesMs.length,
    directDisconnect: m.connectionDirectDisconnectLatencySamplesMs.length,
  );
}

const List<String> _metricsDeltaKeys = <String>[
  'rpc_sql_execute_materialized_response',
  'rpc_sql_execute_streaming_from_db_response',
  'rpc_sql_execute_streaming_chunks_response',
  'multi_result_pool_vacuous_fallback',
  'multi_result_direct_still_vacuous',
  'transactional_batch_direct_path',
  'connection_pool_acquire_failure',
  'connection_pool_release_failure',
  'connection_pool_acquire_latency_ms_total',
  'connection_pool_acquire_latency_samples',
  'connection_pool_release_latency_ms_total',
  'connection_pool_release_latency_samples',
  'connection_pool_wait_latency_ms_total',
  'connection_pool_wait_latency_samples',
  'connection_direct_connect_latency_ms_total',
  'connection_direct_connect_latency_samples',
  'connection_direct_disconnect_latency_ms_total',
  'connection_direct_disconnect_latency_samples',
];

double? _averageMs(int totalMs, int samples) {
  if (samples <= 0) {
    return null;
  }
  return totalMs / samples;
}

Map<String, int> _metricsDelta(
  Map<String, int> before,
  Map<String, int> after,
) {
  return <String, int>{
    for (final key in _metricsDeltaKeys) key: (after[key] ?? 0) - (before[key] ?? 0),
  };
}

Map<String, dynamic> _metricsDerived(Map<String, int> metrics) {
  final acquireAvg = _averageMs(
    metrics['connection_pool_acquire_latency_ms_total'] ?? 0,
    metrics['connection_pool_acquire_latency_samples'] ?? 0,
  );
  final releaseAvg = _averageMs(
    metrics['connection_pool_release_latency_ms_total'] ?? 0,
    metrics['connection_pool_release_latency_samples'] ?? 0,
  );
  final waitAvg = _averageMs(
    metrics['connection_pool_wait_latency_ms_total'] ?? 0,
    metrics['connection_pool_wait_latency_samples'] ?? 0,
  );
  final directConnectAvg = _averageMs(
    metrics['connection_direct_connect_latency_ms_total'] ?? 0,
    metrics['connection_direct_connect_latency_samples'] ?? 0,
  );
  final directDisconnectAvg = _averageMs(
    metrics['connection_direct_disconnect_latency_ms_total'] ?? 0,
    metrics['connection_direct_disconnect_latency_samples'] ?? 0,
  );

  return <String, dynamic>{
    'connection_pool_acquire_latency_avg_ms': ?acquireAvg,
    'connection_pool_release_latency_avg_ms': ?releaseAvg,
    'connection_pool_wait_latency_avg_ms': ?waitAvg,
    'connection_direct_connect_latency_avg_ms': ?directConnectAvg,
    'connection_direct_disconnect_latency_avg_ms': ?directDisconnectAvg,
  };
}

int? _p95FromDeltaSamples(List<int> samples, int startOffset) {
  if (startOffset >= samples.length) {
    return null;
  }
  final delta = samples.sublist(startOffset)..sort();
  final idx = ((delta.length * 0.95).ceil() - 1).clamp(0, delta.length - 1);
  return delta[idx];
}

Map<String, dynamic> _stageLatencyDerived({
  required _LatencySampleOffsets beforeOffsets,
  required MetricsCollector metrics,
  required Map<String, dynamic> caseJson,
}) {
  return <String, dynamic>{
    'db_stage_p95_ms': caseJson['p95_ms'],
    'pool_acquire_p95_ms': _p95FromDeltaSamples(
      metrics.connectionPoolAcquireLatencySamplesMs,
      beforeOffsets.poolAcquire,
    ),
    'pool_release_p95_ms': _p95FromDeltaSamples(
      metrics.connectionPoolReleaseLatencySamplesMs,
      beforeOffsets.poolRelease,
    ),
    'pool_wait_p95_ms': _p95FromDeltaSamples(
      metrics.connectionPoolWaitLatencySamplesMs,
      beforeOffsets.poolWait,
    ),
    'direct_connect_p95_ms': _p95FromDeltaSamples(
      metrics.connectionDirectConnectLatencySamplesMs,
      beforeOffsets.directConnect,
    ),
    'direct_disconnect_p95_ms': _p95FromDeltaSamples(
      metrics.connectionDirectDisconnectLatencySamplesMs,
      beforeOffsets.directDisconnect,
    ),
  };
}

Map<String, dynamic> _attachCaseMetrics(
  Map<String, dynamic> caseJson, {
  required Map<String, int> beforeMetrics,
  required _LatencySampleOffsets beforeLatencyOffsets,
  required MetricsCollector metrics,
}) {
  final delta = _metricsDelta(beforeMetrics, _metricsSnapshot(metrics));
  return <String, dynamic>{
    ...caseJson,
    'metrics_delta': delta,
    'metrics_derived': _metricsDerived(delta),
    'stage_latency_p95_ms': _stageLatencyDerived(
      beforeOffsets: beforeLatencyOffsets,
      metrics: metrics,
      caseJson: caseJson,
    ),
  };
}

bool _multiResultHasPayload(Map<String, dynamic> body) {
  final sets = body['result_sets'] as List<dynamic>? ?? <dynamic>[];
  final rows = body['rows'] as List<dynamic>? ?? <dynamic>[];
  return sets.isNotEmpty || rows.isNotEmpty;
}

void _registerBenchmarkGroup(
  String label,
  String connectionString, {
  required String runId,
  required OdbcE2eBenchmarkProfile profile,
}) {
  group('ODBC RPC benchmark (E2E) — $label', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;
    late OdbcE2eLiveSql sql;
    late MockOdbcConnectionSettings benchmarkSettings;
    late int benchmarkSeedRows;

    setUpAll(() async {
      benchmarkSettings = _benchmarkSettings(profile);
      benchmarkSeedRows = E2EEnv.odbcE2eBenchmarkSeedRows;
      final tableName = newOdbcE2eLiveTableName();
      sql = OdbcE2eLiveSql(
        detectOdbcE2eDialect(connectionString),
        tableName: tableName,
      );
      final opened = await OdbcE2eRpcHarness.open(
        connectionString,
        sql.dialect,
        connectionSettings: benchmarkSettings,
        useSharedLocator: true,
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

      final seed = await opened.gateway.executeBatch(
        'e2e-agent',
        _seedCommands(sql, benchmarkSeedRows),
        options: const SqlExecutionOptions(transaction: true, maxRows: 500),
      );
      expect(seed.isSuccess(), isTrue, reason: 'seed table: $seed');

      isReady = true;
    });

    tearDownAll(() async {
      final h = harness;
      if (h == null) {
        return;
      }
      await h.gateway.executeNonQuery(sql.dropTableIfExists, null);
      await h.shutdown(shutdownLocator: false);
    });

    test(
      'should measure rpc sql.execute / executeBatch and optionally append '
      'JSONL history [${profile.label}]',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        final h = harness!;
        h.metrics.clear();
        final benchmarkConcurrency = profile.concurrency;
        final midId = (benchmarkSeedRows / 2).ceil();
        final batchCommands = _batchReadCommands(sql, benchmarkSeedRows);
        final multiResultSql = _multiResultSql(sql, benchmarkSeedRows);

        var seq = 0;
        String benchId(String kind) => 'bench-$kind-${seq++}';

        final materializedBeforeMetrics = _metricsSnapshot(h.metrics);
        final materializedBeforeLatency = _latencySampleOffsetsSnapshot(
          h.metrics,
        );
        final materialized = await E2eBenchmarkStats.measureAsync(() async {
          final resp = await h.dispatcher.dispatch(
            e2eRpcExecute(
              id: benchId('mat'),
              sql: sql.selectIdCodeAmtOrderById,
            ),
            'e2e-agent',
          );
          expect(resp.isSuccess, isTrue, reason: '${resp.error}');
        });
        final materializedCase = _attachCaseMetrics(
          materialized.toJson(),
          beforeMetrics: materializedBeforeMetrics,
          beforeLatencyOffsets: materializedBeforeLatency,
          metrics: h.metrics,
        );

        final batchReadsBeforeMetrics = _metricsSnapshot(h.metrics);
        final batchReadsBeforeLatency = _latencySampleOffsetsSnapshot(
          h.metrics,
        );
        final batchReads = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecuteBatch(
                id: benchId('batch'),
                commands: batchCommands,
                options: <String, dynamic>{
                  'transaction': false,
                  'max_rows': benchmarkSeedRows,
                },
              ),
              'e2e-agent',
            );
            expect(resp.isSuccess, isTrue, reason: '${resp.error}');
          },
          warmup: 1,
          iterations: 6,
        );
        final batchReadsCase = _attachCaseMetrics(
          batchReads.toJson(),
          beforeMetrics: batchReadsBeforeMetrics,
          beforeLatencyOffsets: batchReadsBeforeLatency,
          metrics: h.metrics,
        );

        final namedParamsBeforeMetrics = _metricsSnapshot(h.metrics);
        final namedParamsBeforeLatency = _latencySampleOffsetsSnapshot(
          h.metrics,
        );
        final namedParams = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecuteWithParams(
                id: benchId('named'),
                sql: sql.selectCodeWhereIdNamed('rid'),
                boundParams: <String, dynamic>{'rid': midId},
              ),
              'e2e-agent',
            );
            expect(resp.isSuccess, isTrue, reason: '${resp.error}');
          },
          warmup: 1,
          iterations: 6,
        );
        final namedParamsCase = _attachCaseMetrics(
          namedParams.toJson(),
          beforeMetrics: namedParamsBeforeMetrics,
          beforeLatencyOffsets: namedParamsBeforeLatency,
          metrics: h.metrics,
        );

        var lastMultiHasPayload = false;
        final multiResultBeforeMetrics = _metricsSnapshot(h.metrics);
        final multiResultBeforeLatency = _latencySampleOffsetsSnapshot(
          h.metrics,
        );
        final multiStats = await E2eBenchmarkStats.measureAsync(
          () async {
            final multiResp = await h.dispatcher.dispatch(
              e2eRpcExecute(
                id: benchId('multi'),
                sql: multiResultSql,
                options: <String, dynamic>{
                  'multi_result': true,
                  'max_rows': benchmarkSeedRows,
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
        final multiResultCase = _attachCaseMetrics(
          <String, dynamic>{
            ...multiStats.toJson(),
            'last_has_payload': lastMultiHasPayload,
          },
          beforeMetrics: multiResultBeforeMetrics,
          beforeLatencyOffsets: multiResultBeforeLatency,
          metrics: h.metrics,
        );

        final batchTxBeforeMetrics = _metricsSnapshot(h.metrics);
        final batchTxBeforeLatency = _latencySampleOffsetsSnapshot(h.metrics);
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
        final batchTxCase = _attachCaseMetrics(
          batchTx.toJson(),
          beforeMetrics: batchTxBeforeMetrics,
          beforeLatencyOffsets: batchTxBeforeLatency,
          metrics: h.metrics,
        );

        final writeDmlBeforeMetrics = _metricsSnapshot(h.metrics);
        final writeDmlBeforeLatency = _latencySampleOffsetsSnapshot(h.metrics);
        final writeDml = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecuteBatch(
                id: benchId('write-dml'),
                commands: _writeDmlCommands(
                  sql,
                  tempId: benchmarkSeedRows + 100000,
                ),
                options: const <String, dynamic>{
                  'transaction': true,
                  'max_rows': 10,
                },
              ),
              'e2e-agent',
            );
            expect(resp.isSuccess, isTrue, reason: '${resp.error}');
          },
          warmup: 1,
          iterations: 4,
        );
        final writeDmlCase = _attachCaseMetrics(
          writeDml.toJson(),
          beforeMetrics: writeDmlBeforeMetrics,
          beforeLatencyOffsets: writeDmlBeforeLatency,
          metrics: h.metrics,
        );

        final timeoutCancelBeforeMetrics = _metricsSnapshot(h.metrics);
        final timeoutCancelBeforeLatency = _latencySampleOffsetsSnapshot(
          h.metrics,
        );
        var timeoutCancelSuccessCount = 0;
        var timeoutCancelFailureCount = 0;
        final timeoutCancel = await E2eBenchmarkStats.measureAsync(
          () async {
            final resp = await h.dispatcher.dispatch(
              e2eRpcExecute(
                id: benchId('timeout-cancel'),
                sql: _timeoutProbeSql(sql),
                options: const <String, dynamic>{'timeout_ms': 1},
              ),
              'e2e-agent',
            );
            if (resp.isSuccess) {
              timeoutCancelSuccessCount++;
            } else {
              timeoutCancelFailureCount++;
            }
          },
          warmup: 1,
          iterations: 3,
        );
        final timeoutCancelCase = _attachCaseMetrics(
          timeoutCancel.toJson(),
          beforeMetrics: timeoutCancelBeforeMetrics,
          beforeLatencyOffsets: timeoutCancelBeforeLatency,
          metrics: h.metrics,
        );
        timeoutCancelCase['timeout_cancel_failure_samples'] = timeoutCancelFailureCount;
        timeoutCancelCase['timeout_cancel_success_samples'] = timeoutCancelSuccessCount;
        if (_requireTimeoutCancelFailure()) {
          expect(
            timeoutCancelFailureCount,
            greaterThan(0),
            reason:
                'Timeout cancel benchmark did not observe a timeout failure. '
                'Increase probe cost or disable ODBC_E2E_BENCHMARK_REQUIRE_TIMEOUT_CANCEL.',
          );
        }

        final streamingBeforeMetrics = _metricsSnapshot(h.metrics);
        final streamingBeforeLatency = _latencySampleOffsetsSnapshot(h.metrics);
        final streaming = await _measureStreamingCaseAsync(
          () async {
            final emitter = OdbcE2eRecordingRpcStreamEmitter();
            final streamResp = await h.dispatcher.dispatch(
              e2eRpcExecute(
                id: benchId('stream'),
                sql: sql.selectIdCodeAmtOrderById,
              ),
              'e2e-agent',
              streamEmitter: emitter,
              limits: const TransportLimits(streamingChunkSize: 32),
            );
            expect(streamResp.isSuccess, isTrue, reason: '${streamResp.error}');
            expect(emitter.complete, isNotNull);
            expect(emitter.complete!.totalRows, benchmarkSeedRows);
            return _StreamingIterationMeasurement(
              firstChunkLatencyMs: emitter.firstChunkLatencyMs ?? 0,
              chunkCount: emitter.chunkCount,
              totalRows: emitter.totalChunkRows,
            );
          },
        );
        final streamingCase = _attachCaseMetrics(
          streaming.toJson(),
          beforeMetrics: streamingBeforeMetrics,
          beforeLatencyOffsets: streamingBeforeLatency,
          metrics: h.metrics,
        );

        late _StreamingCaseMeasurement streamingChunks;
        late Map<String, dynamic> streamingChunksCase;
        when(
          () => h.featureFlags.enableSocketStreamingFromDb,
        ).thenReturn(false);
        try {
          final streamingChunksBeforeMetrics = _metricsSnapshot(h.metrics);
          final streamingChunksBeforeLatency = _latencySampleOffsetsSnapshot(
            h.metrics,
          );
          streamingChunks = await _measureStreamingCaseAsync(
            () async {
              final emitter = OdbcE2eRecordingRpcStreamEmitter();
              final streamResp = await h.dispatcher.dispatch(
                e2eRpcExecute(
                  id: benchId('stream-chunks'),
                  sql: sql.selectIdCodeAmtOrderById,
                ),
                'e2e-agent',
                streamEmitter: emitter,
                limits: const TransportLimits(
                  streamingChunkSize: 16,
                  streamingRowThreshold: 1,
                ),
              );
              expect(
                streamResp.isSuccess,
                isTrue,
                reason: '${streamResp.error}',
              );
              expect(emitter.complete, isNotNull);
              expect(emitter.complete!.totalRows, benchmarkSeedRows);
              return _StreamingIterationMeasurement(
                firstChunkLatencyMs: emitter.firstChunkLatencyMs ?? 0,
                chunkCount: emitter.chunkCount,
                totalRows: emitter.totalChunkRows,
              );
            },
          );
          streamingChunksCase = _attachCaseMetrics(
            streamingChunks.toJson(),
            beforeMetrics: streamingChunksBeforeMetrics,
            beforeLatencyOffsets: streamingChunksBeforeLatency,
            metrics: h.metrics,
          );
        } finally {
          when(
            () => h.featureFlags.enableSocketStreamingFromDb,
          ).thenReturn(true);
        }

        Map<String, dynamic>? materializedParallel;
        Map<String, dynamic>? batchReadsParallel;
        Map<String, dynamic>? multiResultParallel;
        Map<String, dynamic>? writeDmlParallel;
        var parallelMultiHasPayload = true;
        if (benchmarkConcurrency > 1) {
          final materializedParallelBeforeMetrics = _metricsSnapshot(h.metrics);
          final materializedParallelBeforeLatency = _latencySampleOffsetsSnapshot(
            h.metrics,
          );
          final materializedParallelStats = await _measureConcurrentAsync(
            (int invocation) async {
              final resp = await h.dispatcher.dispatch(
                e2eRpcExecute(
                  id: benchId('mat-par-$invocation'),
                  sql: sql.selectIdCodeAmtOrderById,
                ),
                'e2e-agent',
              );
              expect(resp.isSuccess, isTrue, reason: '${resp.error}');
            },
            concurrency: benchmarkConcurrency,
          );
          materializedParallel = _attachCaseMetrics(
            _statsWithConcurrency(
              materializedParallelStats,
              concurrency: benchmarkConcurrency,
            ),
            beforeMetrics: materializedParallelBeforeMetrics,
            beforeLatencyOffsets: materializedParallelBeforeLatency,
            metrics: h.metrics,
          );

          final batchReadsParallelBeforeMetrics = _metricsSnapshot(h.metrics);
          final batchReadsParallelBeforeLatency = _latencySampleOffsetsSnapshot(
            h.metrics,
          );
          final batchReadsParallelStats = await _measureConcurrentAsync(
            (int invocation) async {
              final resp = await h.dispatcher.dispatch(
                e2eRpcExecuteBatch(
                  id: benchId('batch-par-$invocation'),
                  commands: batchCommands,
                  options: <String, dynamic>{
                    'transaction': false,
                    'max_rows': benchmarkSeedRows,
                  },
                ),
                'e2e-agent',
              );
              expect(resp.isSuccess, isTrue, reason: '${resp.error}');
            },
            concurrency: benchmarkConcurrency,
          );
          batchReadsParallel = _attachCaseMetrics(
            _statsWithConcurrency(
              batchReadsParallelStats,
              concurrency: benchmarkConcurrency,
            ),
            beforeMetrics: batchReadsParallelBeforeMetrics,
            beforeLatencyOffsets: batchReadsParallelBeforeLatency,
            metrics: h.metrics,
          );

          final multiResultParallelBeforeMetrics = _metricsSnapshot(h.metrics);
          final multiResultParallelBeforeLatency = _latencySampleOffsetsSnapshot(
            h.metrics,
          );
          final multiResultParallelStats = await _measureConcurrentAsync(
            (int invocation) async {
              final resp = await h.dispatcher.dispatch(
                e2eRpcExecute(
                  id: benchId('multi-par-$invocation'),
                  sql: multiResultSql,
                  options: <String, dynamic>{
                    'multi_result': true,
                    'max_rows': benchmarkSeedRows,
                  },
                ),
                'e2e-agent',
              );
              expect(resp.isSuccess, isTrue, reason: '${resp.error}');
              final body = resp.result! as Map<String, dynamic>;
              parallelMultiHasPayload = parallelMultiHasPayload && _multiResultHasPayload(body);
            },
            concurrency: benchmarkConcurrency,
            iterations: 3,
          );
          multiResultParallel = _attachCaseMetrics(
            <String, dynamic>{
              ..._statsWithConcurrency(
                multiResultParallelStats,
                concurrency: benchmarkConcurrency,
              ),
              'last_has_payload': parallelMultiHasPayload,
            },
            beforeMetrics: multiResultParallelBeforeMetrics,
            beforeLatencyOffsets: multiResultParallelBeforeLatency,
            metrics: h.metrics,
          );

          final writeDmlParallelBeforeMetrics = _metricsSnapshot(h.metrics);
          final writeDmlParallelBeforeLatency = _latencySampleOffsetsSnapshot(
            h.metrics,
          );
          final writeDmlParallelStats = await _measureConcurrentAsync(
            (int invocation) async {
              final tempId = benchmarkSeedRows + 200000 + invocation + 1;
              final resp = await h.dispatcher.dispatch(
                e2eRpcExecuteBatch(
                  id: benchId('write-dml-par-$invocation'),
                  commands: _writeDmlCommands(sql, tempId: tempId),
                  options: const <String, dynamic>{
                    'transaction': true,
                    'max_rows': 10,
                  },
                ),
                'e2e-agent',
              );
              expect(resp.isSuccess, isTrue, reason: '${resp.error}');
            },
            concurrency: benchmarkConcurrency,
          );
          writeDmlParallel = _attachCaseMetrics(
            _statsWithConcurrency(
              writeDmlParallelStats,
              concurrency: benchmarkConcurrency,
            ),
            beforeMetrics: writeDmlParallelBeforeMetrics,
            beforeLatencyOffsets: writeDmlParallelBeforeLatency,
            metrics: h.metrics,
          );
        }

        final cases = <String, dynamic>{
          _caseMaterialized: materializedCase,
          _caseBatchReads: batchReadsCase,
          _caseNamedParams: namedParamsCase,
          _caseMultiResult: multiResultCase,
          _caseBatchTx: batchTxCase,
          _caseWriteDml: writeDmlCase,
          _caseTimeoutCancel: timeoutCancelCase,
          _caseStreamingDb: streamingCase,
          _caseStreamingChunks: streamingChunksCase,
          _caseMaterializedParallel: ?materializedParallel,
          _caseBatchReadsParallel: ?batchReadsParallel,
          _caseMultiResultParallel: ?multiResultParallel,
          _caseWriteDmlParallel: ?writeDmlParallel,
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
          if (multiResultParallel != null) {
            expect(
              parallelMultiHasPayload,
              isTrue,
              reason:
                  'parallel multi_result benchmark returned an empty payload in '
                  'at least one invocation',
            );
          }
        }

        final caps = E2EEnv.odbcE2eBenchmarkMaxMsByCase;
        if (caps.isNotEmpty) {
          assertE2eBenchmarkWithinThresholds(cases: cases, thresholds: caps);
        }

        final baselineFile = E2EEnv.odbcE2eBenchmarkBaselineFile;
        final maxRegressionPercent = E2EEnv.odbcE2eBenchmarkMaxRegressionPercent;
        if (baselineFile != null && maxRegressionPercent != null) {
          final comparableBaseline = selectComparableE2eBenchmarkRecords(
            records: _loadBaselineRecords(baselineFile),
            targetLabel: label,
            buildMode: _e2eFlutterBenchmarkBuildMode(),
            benchmarkProfile: _benchmarkProfile(profile, benchmarkSettings),
            databaseHosting: E2EEnv.odbcE2eBenchmarkDbHosting,
          );
          assertE2eBenchmarkWithinRegressionBudget(
            cases: cases,
            baselineRecords: comparableBaseline,
            maxRegressionPercent: maxRegressionPercent,
            maxRegressionMs: E2EEnv.odbcE2eBenchmarkMaxRegressionMs,
            window: E2EEnv.odbcE2eBenchmarkBaselineWindow,
          );
        }

        if (E2EEnv.odbcE2eBenchmarkRecordEnabled) {
          final out = resolveE2eBenchmarkOutputFile(
            E2EEnv.odbcE2eBenchmarkRecordFile,
          );
          final hosting = E2EEnv.odbcE2eBenchmarkDbHosting;
          final metricsCounters = _metricsSnapshot(h.metrics);
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
              'benchmark_profile': _benchmarkProfile(
                profile,
                benchmarkSettings,
              ),
              'metrics_counters': metricsCounters,
              'metrics_derived': _metricsDerived(metricsCounters),
              'cases': cases,
            },
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
