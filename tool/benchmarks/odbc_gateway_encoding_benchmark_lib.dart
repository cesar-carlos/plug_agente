// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';

import 'odbc_benchmark_fixture.dart';

Future<Map<String, Object?>> runOdbcGatewayEncodingBenchmark({
  required String dsn,
  String? sql,
  int iterations = 6,
}) async {
  if (iterations <= 0) throw ArgumentError.value(iterations, 'iterations');
  final native = NativeOdbcConnection();
  if (!native.initialize()) throw StateError('Benchmark initialization failed');
  final connection = native.connect(dsn);
  if (connection == 0) throw StateError('Benchmark connection failed');
  final fixture = OdbcBenchmarkFixture(native, connection);
  final results = <Map<String, Object>>[];
  try {
    await fixture.create();
    final driver = benchmarkDriverMetadata(native, connection);
    for (final profile in [OdbcUsageProfile.balancedServer, OdbcUsageProfile.highThroughput]) {
      final locator = ServiceLocator()
        ..initialize(profile: profile, useAsync: true, asyncWorkerCount: 2, asyncMaxPendingRequests: 8);
      final service = locator.service;
      String? connectionId;
      try {
        (await service.initialize()).getOrThrow();
        connectionId = (await service.connect(dsn)).getOrThrow().id;
        final executor = OdbcResultEncodingExecutor(service);
        final samples = <int>[];
        for (var index = -1; index < iterations; index++) {
          final timer = Stopwatch()..start();
          final result = (await executor.execute(
            connectionId,
            OdbcPreparedQueryExecution(sql: sql ?? fixture.query, parameters: null),
          )).getOrThrow();
          timer.stop();
          validateBenchmarkRows(result.rows);
          if (index >= 0) samples.add(timer.elapsedMicroseconds);
        }
        samples.sort();
        results.add({
          'scenario': '${profile.name}_rowMajor',
          'result_encoding': ResultEncoding.rowMajor.name,
          'profile': profile.name,
          'rows': OdbcBenchmarkFixture.rowCount,
          'iterations': iterations,
          'median_us': samples[samples.length ~/ 2],
          'min_us': samples.first,
          'max_us': samples.last,
        });
      } finally {
        try {
          if (connectionId != null) (await service.disconnect(connectionId)).getOrThrow();
        } finally {
          locator.shutdown();
        }
      }
    }
    return {
      'benchmark': 'gateway_materialized_rowMajor',
      'harness_version': 2,
      'driver': driver,
      'workload': 'deterministic_8000_rows_v1',
      'scenarios': results,
    };
  } finally {
    try {
      fixture.dispose();
    } finally {
      native.disconnect(connection);
    }
  }
}

Future<void> runOdbcGatewayEncodingBenchmarkCli(List<String> args) async {
  await AppEnvironment.loadOptional();
  final dsn = _readArg(args, '--dsn') ?? Platform.environment['ODBC_TEST_DSN'] ?? Platform.environment['ODBC_DSN'];
  if (dsn == null || dsn.isEmpty) {
    stderr.writeln('Skipping: set ODBC_TEST_DSN / ODBC_DSN');
    return;
  }
  final payload = await runOdbcGatewayEncodingBenchmark(
    dsn: dsn,
    sql: _readArg(args, '--sql') ?? Platform.environment['ODBC_BENCH_QUERY'],
    iterations: int.parse(_readArg(args, '--iterations') ?? '6'),
  );
  print(jsonEncode(payload));
}

String? _readArg(List<String> args, String name) {
  final index = args.indexOf(name);
  return index < 0 ? null : args[index + 1];
}
