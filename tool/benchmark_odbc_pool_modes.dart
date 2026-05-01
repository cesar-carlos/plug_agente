import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';

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
  final iterations = _readIntArg(args, '--iterations') ?? 24;
  final concurrency = _readIntArg(args, '--concurrency') ?? 4;
  final poolSize = _readIntArg(args, '--pool-size') ?? 8;
  final warmupIterations = _readIntArg(args, '--warmup-iterations') ?? min(5, iterations);

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

  final scenarios = <({String name, IConnectionPool pool})>[
    (
      name: 'lease_pool',
      pool: OdbcConnectionPool(
        service,
        leaseSettings,
      ),
    ),
    (
      name: 'native_pool',
      pool: OdbcNativeConnectionPool(
        service,
        nativeSettings,
      ),
    ),
    (
      name: 'native_pool_no_checkout_validation',
      pool: OdbcNativeConnectionPool(
        service,
        nativeNoCheckoutSettings,
      ),
    ),
  ];

  stdout.writeln('# ODBC Pool Benchmark');
  stdout.writeln('- service_mode: async_worker');
  stdout.writeln('- iterations: $iterations');
  stdout.writeln('- concurrency: $concurrency');
  stdout.writeln('- pool_size: $poolSize');
  stdout.writeln('- warmup_iterations: $warmupIterations');
  stdout.writeln('- query: $query');
  stdout.writeln();
  stdout.writeln('| scenario | avg_ms | p95_ms | ok | fail |');
  stdout.writeln('| --- | ---: | ---: | ---: | ---: |');

  for (final scenario in scenarios) {
    final result = await _runScenario(
      pool: scenario.pool,
      service: service,
      connectionString: connectionString,
      query: query,
      iterations: iterations,
      concurrency: concurrency,
      warmupIterations: warmupIterations,
    );
    stdout.writeln(
      '| ${scenario.name} | ${result.avgMs.toStringAsFixed(2)} | '
      '${result.p95Ms.toStringAsFixed(2)} | ${result.okCount} | '
      '${result.failCount} |',
    );
    await scenario.pool.closeAll();
  }

  locator.shutdown();
}

Future<_ScenarioResult> _runScenario({
  required IConnectionPool pool,
  required OdbcService service,
  required String connectionString,
  required String query,
  required int iterations,
  required int concurrency,
  required int warmupIterations,
}) async {
  final latenciesMs = <double>[];
  var okCount = 0;
  var failCount = 0;
  var cursor = 0;

  if (warmupIterations > 0) {
    for (var i = 0; i < warmupIterations; i++) {
      final acquired = await pool.acquire(connectionString);
      if (acquired.isError()) {
        continue;
      }
      final connectionId = acquired.getOrThrow();
      try {
        await service.executeQuery(
          query,
          connectionId: connectionId,
        );
      } finally {
        await pool.release(connectionId);
      }
    }
  }

  Future<void> worker() async {
    while (true) {
      final index = cursor++;
      if (index >= iterations) {
        return;
      }

      final stopwatch = Stopwatch()..start();
      final acquired = await pool.acquire(connectionString);
      if (acquired.isError()) {
        stopwatch.stop();
        failCount++;
        continue;
      }

      final connectionId = acquired.getOrThrow();
      try {
        final result = await service.executeQuery(
          query,
          connectionId: connectionId,
        );
        stopwatch.stop();
        latenciesMs.add(stopwatch.elapsedMicroseconds / 1000);
        if (result.isSuccess()) {
          okCount++;
        } else {
          failCount++;
        }
      } finally {
        await pool.release(connectionId);
      }
    }
  }

  await Future.wait(
    List.generate(max(1, concurrency), (_) => worker()),
  );
  latenciesMs.sort();

  return _ScenarioResult(
    avgMs: latenciesMs.isEmpty ? 0 : latenciesMs.reduce((a, b) => a + b) / latenciesMs.length,
    p95Ms: latenciesMs.isEmpty ? 0 : latenciesMs[(latenciesMs.length * 0.95).floor().clamp(0, latenciesMs.length - 1)],
    okCount: okCount,
    failCount: failCount,
  );
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

class _ScenarioResult {
  const _ScenarioResult({
    required this.avgMs,
    required this.p95Ms,
    required this.okCount,
    required this.failCount,
  });

  final double avgMs;
  final double p95Ms;
  final int okCount;
  final int failCount;
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
