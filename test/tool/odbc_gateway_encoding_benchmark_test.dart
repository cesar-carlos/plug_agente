import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/app_environment.dart';

import '../../tool/benchmarks/odbc_gateway_encoding_benchmark_lib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dsn = Platform.environment['ODBC_TEST_DSN']?.trim() ?? Platform.environment['ODBC_DSN']?.trim();
  final skipReason = dsn == null || dsn.isEmpty
      ? 'Set ODBC_TEST_DSN or ODBC_DSN to run gateway encoding benchmark.'
      : null;

  test(
    'odbc gateway encoding benchmark',
    () async {
      await AppEnvironment.loadOptional();

      final resolvedDsn =
          Platform.environment['ODBC_TEST_DSN']?.trim() ?? Platform.environment['ODBC_DSN']?.trim() ?? dsn;
      final sql = Platform.environment['ODBC_BENCH_QUERY'] ?? resolveDefaultOdbcBenchQuery(dsn: resolvedDsn);
      final payload = await runOdbcGatewayEncodingBenchmark(
        dsn: resolvedDsn!,
        sql: sql,
        iterations: 4,
      );

      expect(payload, isNotNull);
      stdout.writeln(jsonEncode(payload));

      final scenarios = payload!['scenarios']! as List<dynamic>;
      expect(scenarios, isNotEmpty);
      for (final scenario in scenarios) {
        final map = scenario as Map<String, dynamic>;
        expect(map['median_us'], isA<int>());
      }
    },
    skip: skipReason,
    timeout: Timeout.none,
    tags: const ['perf'],
  );
}
