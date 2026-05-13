import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

Future<void> main(List<String> args) async {
  final connectionString =
      _readStringArg(args, '--connection-string') ?? Platform.environment['ODBC_BENCH_CONNECTION_STRING'];
  if (connectionString == null || connectionString.trim().isEmpty) {
    stderr.writeln(
      'Missing connection string. Use --connection-string or '
      'ODBC_BENCH_CONNECTION_STRING.',
    );
    exitCode = 64;
    return;
  }

  final query = _readStringArg(args, '--query') ?? Platform.environment['ODBC_BENCH_QUERY'] ?? 'SELECT 1';
  final driver = _readStringArg(args, '--driver') ?? Platform.environment['ODBC_BENCH_DRIVER'] ?? 'SQL Server';
  final iterations = _readIntArg(args, '--iterations') ?? 24;
  final concurrency = _readIntArg(args, '--concurrency') ?? 4;
  final burstConcurrency = _readIntArg(args, '--burst-concurrency') ?? max(concurrency, 12);
  final batchSize = _readIntArg(args, '--batch-size') ?? 10;
  final poolSize = _readIntArg(args, '--pool-size') ?? 8;
  final warmupIterations = _readIntArg(args, '--warmup-iterations') ?? min(5, iterations);
  final jsonOutput = _hasFlag(args, '--json');
  final jsonOnlyOutput = _hasFlag(args, '--json-only');

  final locator = ServiceLocator()..initialize(useAsync: true);
  final service = locator.asyncService;
  final initResult = await service.initialize();
  if (initResult.isError()) {
    stderr.writeln('Failed to initialize ODBC: ${initResult.exceptionOrNull()}');
    exitCode = 1;
    return;
  }

  final leaseSettings = _BenchmarkConnectionSettings(poolSize: poolSize);
  final nativeSettings = _BenchmarkConnectionSettings(
    poolSize: poolSize,
    useNativeOdbcPool: true,
  );
  final nativeNoCheckoutSettings = _BenchmarkConnectionSettings(
    poolSize: poolSize,
    useNativeOdbcPool: true,
    nativePoolTestOnCheckout: false,
  );
  final adaptiveFlags = FeatureFlags(InMemoryAppSettingsStore());
  await adaptiveFlags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
  final adaptiveSettings = _BenchmarkConnectionSettings(poolSize: poolSize);
  final leaseMetrics = MetricsCollector();
  final nativeMetrics = MetricsCollector();
  final nativeNoCheckoutMetrics = MetricsCollector();
  final adaptiveMetrics = MetricsCollector();

  final scenarios = <({String name, IConnectionPool pool, MetricsCollector metrics})>[
    (
      name: 'lease_pool',
      pool: OdbcConnectionPool(
        service,
        leaseSettings,
        metricsCollector: leaseMetrics,
      ),
      metrics: leaseMetrics,
    ),
    (
      name: 'native_pool',
      pool: OdbcNativeConnectionPool(
        service,
        nativeSettings,
        metricsCollector: nativeMetrics,
      ),
      metrics: nativeMetrics,
    ),
    (
      name: 'native_pool_no_checkout_validation',
      pool: OdbcNativeConnectionPool(
        service,
        nativeNoCheckoutSettings,
        metricsCollector: nativeNoCheckoutMetrics,
      ),
      metrics: nativeNoCheckoutMetrics,
    ),
    (
      name: 'adaptive_experimental',
      pool: AdaptiveOdbcConnectionPool(
        leasePool: OdbcConnectionPool(
          service,
          adaptiveSettings,
          metricsCollector: adaptiveMetrics,
        ),
        nativePool: OdbcNativeConnectionPool(
          service,
          adaptiveSettings,
          metricsCollector: adaptiveMetrics,
        ),
        featureFlags: adaptiveFlags,
        metricsCollector: adaptiveMetrics,
        configRepository: _BenchmarkConfigRepository(
          driverName: driver,
          connectionString: connectionString,
        ),
        nativeWarmUpEnabled: true,
      ),
      metrics: adaptiveMetrics,
    ),
  ];

  final workloads = <_Workload>[
    _Workload.simple(
      name: 'simple_repeated',
      iterations: iterations,
      concurrency: concurrency,
    ),
    _Workload.batch(
      name: 'batch_single_lease',
      iterations: max(1, iterations ~/ batchSize),
      batchSize: batchSize,
    ),
    _Workload.simple(
      name: 'burst_concurrent',
      iterations: iterations,
      concurrency: burstConcurrency,
    ),
  ];

  if (!jsonOnlyOutput) {
    stdout.writeln('# ODBC Pool Benchmark');
    stdout.writeln('- service_mode: async_worker');
    stdout.writeln('- driver: $driver');
    stdout.writeln('- iterations: $iterations');
    stdout.writeln('- concurrency: $concurrency');
    stdout.writeln('- burst_concurrency: $burstConcurrency');
    stdout.writeln('- batch_size: $batchSize');
    stdout.writeln('- pool_size: $poolSize');
    stdout.writeln('- warmup_iterations: $warmupIterations');
    stdout.writeln('- query: $query');
    stdout.writeln();
    stdout.writeln('| pool | workload | avg_ms | p50_ms | p95_ms | p99_ms | ops_sec | ok | fail |');
    stdout.writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  }

  final jsonResults = <Map<String, Object?>>[];
  for (final scenario in scenarios) {
    for (final workload in workloads) {
      final result = await _runScenario(
        pool: scenario.pool,
        service: service,
        metrics: scenario.metrics,
        connectionString: connectionString,
        query: query,
        workload: workload,
        warmupIterations: warmupIterations,
      );
      if (!jsonOnlyOutput) {
        stdout.writeln(
          '| ${scenario.name} | ${workload.name} | ${result.avgMs.toStringAsFixed(2)} | '
          '${result.p50Ms.toStringAsFixed(2)} | ${result.p95Ms.toStringAsFixed(2)} | '
          '${result.p99Ms.toStringAsFixed(2)} | ${result.opsPerSecond.toStringAsFixed(2)} | '
          '${result.okCount} | ${result.failCount} |',
        );
      }
      jsonResults.add({
        'pool': scenario.name,
        'workload': workload.name,
        ...result.toJson(),
        'metrics': scenario.metrics.getSnapshot(),
        'pool_diagnostics': switch (scenario.pool) {
          final IConnectionPoolDiagnostics diagnosticsPool => diagnosticsPool.getHealthDiagnostics(),
          _ => const <String, Object?>{},
        },
      });
    }
    await scenario.pool.closeAll();
  }

  if (jsonOutput || jsonOnlyOutput) {
    if (!jsonOnlyOutput) {
      stdout.writeln();
    }
    stdout.writeln(
      jsonEncode({
        'service_mode': 'async_worker',
        'driver': driver,
        'iterations': iterations,
        'concurrency': concurrency,
        'burst_concurrency': burstConcurrency,
        'batch_size': batchSize,
        'pool_size': poolSize,
        'warmup_iterations': warmupIterations,
        'query': query,
        'rss_bytes': ProcessInfo.currentRss,
        'results': jsonResults,
      }),
    );
  }

  locator.shutdown();
}

Future<_ScenarioResult> _runScenario({
  required IConnectionPool pool,
  required OdbcService service,
  required MetricsCollector metrics,
  required String connectionString,
  required String query,
  required _Workload workload,
  required int warmupIterations,
}) async {
  await pool.closeAll();
  final coldStart = await _executeOne(
    pool: pool,
    service: service,
    connectionString: connectionString,
    query: query,
  );
  await pool.closeAll();

  if (pool case final IConnectionPoolWarmUp warmUpPool when warmupIterations > 0) {
    await warmUpPool.warmUp(
      connectionString,
      warmUpCount: warmupIterations,
    );
  }
  metrics.clear();
  final rssBefore = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();

  final result = await (switch (workload.kind) {
    _WorkloadKind.simple => _runSimpleScenario(
      pool: pool,
      service: service,
      connectionString: connectionString,
      query: query,
      iterations: workload.iterations,
      concurrency: workload.concurrency,
    ),
    _WorkloadKind.batch => _runBatchScenario(
      pool: pool,
      service: service,
      connectionString: connectionString,
      query: query,
      iterations: workload.iterations,
      batchSize: workload.batchSize,
    ),
  });
  stopwatch.stop();
  return result.copyWith(
    coldStartMs: coldStart.elapsedMs,
    totalDuration: stopwatch.elapsed,
    rssBytesBefore: rssBefore,
    rssBytes: ProcessInfo.currentRss,
  );
}

Future<_ScenarioResult> _runSimpleScenario({
  required IConnectionPool pool,
  required OdbcService service,
  required String connectionString,
  required String query,
  required int iterations,
  required int concurrency,
}) async {
  final latenciesMs = <double>[];
  final errorCategories = <String, int>{};
  var okCount = 0;
  var failCount = 0;
  var cursor = 0;

  Future<void> worker() async {
    while (true) {
      final index = cursor++;
      if (index >= iterations) {
        return;
      }

      final result = await _executeOne(
        pool: pool,
        service: service,
        connectionString: connectionString,
        query: query,
      );
      latenciesMs.add(result.elapsedMs);
      if (result.ok) {
        okCount++;
      } else {
        failCount++;
        _recordErrorCategory(errorCategories, result.errorCategory);
      }
    }
  }

  await Future.wait(
    List.generate(max(1, concurrency), (_) => worker()),
  );
  return _summarize(latenciesMs, okCount, failCount, errorCategories);
}

Future<_ScenarioResult> _runBatchScenario({
  required IConnectionPool pool,
  required OdbcService service,
  required String connectionString,
  required String query,
  required int iterations,
  required int batchSize,
}) async {
  final latenciesMs = <double>[];
  final errorCategories = <String, int>{};
  var okCount = 0;
  var failCount = 0;

  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    final acquired = await pool.acquire(connectionString);
    if (acquired.isError()) {
      stopwatch.stop();
      latenciesMs.add(stopwatch.elapsedMicroseconds / 1000);
      failCount++;
      _recordErrorCategory(errorCategories, acquired.exceptionOrNull());
      continue;
    }

    final connectionId = acquired.getOrThrow();
    try {
      var batchOk = true;
      for (var command = 0; command < batchSize; command++) {
        final result = await service.executeQuery(
          query,
          connectionId: connectionId,
        );
        if (result.isError()) {
          batchOk = false;
          _recordErrorCategory(errorCategories, result.exceptionOrNull());
          break;
        }
      }
      stopwatch.stop();
      latenciesMs.add(stopwatch.elapsedMicroseconds / 1000);
      if (batchOk) {
        okCount++;
      } else {
        failCount++;
      }
    } finally {
      await pool.release(connectionId);
    }
  }

  return _summarize(latenciesMs, okCount, failCount, errorCategories);
}

Future<_ExecutionResult> _executeOne({
  required IConnectionPool pool,
  required OdbcService service,
  required String connectionString,
  required String query,
}) async {
  final stopwatch = Stopwatch()..start();
  final acquired = await pool.acquire(connectionString);
  if (acquired.isError()) {
    stopwatch.stop();
    return _ExecutionResult(
      elapsedMs: stopwatch.elapsedMicroseconds / 1000,
      ok: false,
      errorCategory: acquired.exceptionOrNull(),
    );
  }

  final connectionId = acquired.getOrThrow();
  try {
    final result = await service.executeQuery(
      query,
      connectionId: connectionId,
    );
    stopwatch.stop();
    return _ExecutionResult(
      elapsedMs: stopwatch.elapsedMicroseconds / 1000,
      ok: result.isSuccess(),
      errorCategory: result.exceptionOrNull(),
    );
  } finally {
    await pool.release(connectionId);
  }
}

_ScenarioResult _summarize(
  List<double> latenciesMs,
  int okCount,
  int failCount,
  Map<String, int> errorCategories,
) {
  latenciesMs.sort();
  return _ScenarioResult(
    avgMs: latenciesMs.isEmpty ? 0 : latenciesMs.reduce((a, b) => a + b) / latenciesMs.length,
    p50Ms: latenciesMs.isEmpty ? 0 : latenciesMs[(latenciesMs.length * 0.50).floor().clamp(0, latenciesMs.length - 1)],
    p95Ms: latenciesMs.isEmpty ? 0 : latenciesMs[(latenciesMs.length * 0.95).floor().clamp(0, latenciesMs.length - 1)],
    p99Ms: latenciesMs.isEmpty ? 0 : latenciesMs[(latenciesMs.length * 0.99).floor().clamp(0, latenciesMs.length - 1)],
    okCount: okCount,
    failCount: failCount,
    errorCategories: Map.unmodifiable(errorCategories),
    rssBytes: ProcessInfo.currentRss,
    rssBytesBefore: ProcessInfo.currentRss,
    totalDuration: Duration.zero,
    coldStartMs: 0,
  );
}

void _recordErrorCategory(Map<String, int> categories, Object? error) {
  final category = _errorCategory(error);
  categories[category] = (categories[category] ?? 0) + 1;
}

String _errorCategory(Object? error) {
  if (error == null) {
    return 'unknown';
  }
  if (error is domain.Failure) {
    final reason = error.context['reason'];
    if (reason is String && reason.isNotEmpty) {
      return reason;
    }
    return error.runtimeType.toString();
  }
  return error.runtimeType.toString();
}

String? _readStringArg(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}

int? _readIntArg(List<String> args, String name) {
  final raw = _readStringArg(args, name);
  return raw == null ? null : int.tryParse(raw);
}

bool _hasFlag(List<String> args, String name) => args.contains(name);

enum _WorkloadKind { simple, batch }

class _Workload {
  const _Workload.simple({
    required this.name,
    required this.iterations,
    required this.concurrency,
  }) : kind = _WorkloadKind.simple,
       batchSize = 1;

  const _Workload.batch({
    required this.name,
    required this.iterations,
    required this.batchSize,
  }) : kind = _WorkloadKind.batch,
       concurrency = 1;

  final String name;
  final _WorkloadKind kind;
  final int iterations;
  final int concurrency;
  final int batchSize;
}

class _ExecutionResult {
  const _ExecutionResult({
    required this.elapsedMs,
    required this.ok,
    this.errorCategory,
  });

  final double elapsedMs;
  final bool ok;
  final Object? errorCategory;
}

class _ScenarioResult {
  const _ScenarioResult({
    required this.avgMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.okCount,
    required this.failCount,
    required this.errorCategories,
    required this.rssBytes,
    required this.rssBytesBefore,
    required this.totalDuration,
    required this.coldStartMs,
  });

  final double avgMs;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final int okCount;
  final int failCount;
  final Map<String, int> errorCategories;
  final int rssBytes;
  final int rssBytesBefore;
  final Duration totalDuration;
  final double coldStartMs;

  double get opsPerSecond {
    if (totalDuration == Duration.zero) {
      return 0;
    }
    return (okCount + failCount) / (totalDuration.inMicroseconds / Duration.microsecondsPerSecond);
  }

  int get rssDeltaBytes => rssBytes - rssBytesBefore;

  _ScenarioResult copyWith({
    int? rssBytes,
    int? rssBytesBefore,
    Duration? totalDuration,
    double? coldStartMs,
  }) {
    return _ScenarioResult(
      avgMs: avgMs,
      p50Ms: p50Ms,
      p95Ms: p95Ms,
      p99Ms: p99Ms,
      okCount: okCount,
      failCount: failCount,
      errorCategories: errorCategories,
      rssBytes: rssBytes ?? this.rssBytes,
      rssBytesBefore: rssBytesBefore ?? this.rssBytesBefore,
      totalDuration: totalDuration ?? this.totalDuration,
      coldStartMs: coldStartMs ?? this.coldStartMs,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'avg_ms': avgMs,
      'p50_ms': p50Ms,
      'p95_ms': p95Ms,
      'p99_ms': p99Ms,
      'ops_per_second': opsPerSecond,
      'cold_start_ms': coldStartMs,
      'ok': okCount,
      'fail': failCount,
      'error_categories': errorCategories,
      'rss_bytes': rssBytes,
      'rss_delta_bytes': rssDeltaBytes,
    };
  }
}

class _BenchmarkConfigRepository implements IAgentConfigRepository {
  const _BenchmarkConfigRepository({
    required this.driverName,
    required this.connectionString,
  });

  final String driverName;
  final String connectionString;

  @override
  Future<Result<Config>> getCurrentConfig() async => Success(_config());

  @override
  Future<Result<List<Config>>> getAll() async => Success([_config()]);

  @override
  Future<Result<Config>> getById(String id) async => Success(_config().copyWith(id: id));

  @override
  Future<Result<Config>> save(Config config) async => Success(config);

  @override
  Future<Result<void>> delete(String id) async => Failure(domain.NotFoundFailure('Benchmark repository is read-only'));

  Config _config() {
    return Config(
      id: 'benchmark',
      driverName: driverName,
      odbcDriverName: driverName,
      connectionString: connectionString,
      username: '',
      databaseName: '',
      host: '',
      port: 0,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
  }
}

class _BenchmarkConnectionSettings implements IOdbcConnectionSettings {
  const _BenchmarkConnectionSettings({
    this.poolSize = 8,
    this.useNativeOdbcPool = false,
    this.nativePoolTestOnCheckout = true,
  });

  @override
  final int poolSize;

  @override
  int get loginTimeoutSeconds => 30;

  @override
  int get maxResultBufferMb => 32;

  @override
  int get streamingChunkSizeKb => 1024;

  @override
  final bool useNativeOdbcPool;

  @override
  final bool nativePoolTestOnCheckout;

  @override
  Future<void> load() async {}

  @override
  Future<void> setLoginTimeoutSeconds(int value) async {}

  @override
  Future<void> setMaxResultBufferMb(int value) async {}

  @override
  Future<void> setNativePoolTestOnCheckout(bool value) async {}

  @override
  Future<void> setPoolSize(int value) async {}

  @override
  Future<void> setStreamingChunkSizeKb(int value) async {}

  @override
  Future<void> setUseNativeOdbcPool(bool value) async {}
}
