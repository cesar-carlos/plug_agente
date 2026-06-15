// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_policy.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';

Future<void> main(List<String> args) async {
  await AppEnvironment.loadOptional();

  final dsn = _readArg(args, '--dsn') ?? Platform.environment['ODBC_TEST_DSN'] ?? Platform.environment['ODBC_DSN'];
  if (dsn == null || dsn.trim().isEmpty) {
    stderr.writeln('Skipping: set ODBC_TEST_DSN / ODBC_DSN or pass --dsn');
    exitCode = 0;
    return;
  }

  final sql = _readArg(args, '--sql') ?? Platform.environment['ODBC_BENCH_QUERY'] ?? 'SELECT TOP 1000 * FROM sys.objects';
  final iterations = int.tryParse(_readArg(args, '--iterations') ?? '6') ?? 6;
  final jsonOutput = args.contains('--json');

  final scenarios = <({String name, OdbcUsageProfile? profile, String? encodingEnv})>[
    (name: 'balancedServer_rowMajor', profile: OdbcUsageProfile.balancedServer, encodingEnv: null),
    (name: 'highThroughput_columnar', profile: OdbcUsageProfile.highThroughput, encodingEnv: null),
    (name: 'explicit_columnarCompressed', profile: null, encodingEnv: 'columnarCompressed'),
  ];

  final locator = ServiceLocator()
    ..initialize(
      profile: resolveOdbcUsageProfile(),
      useAsync: true,
      asyncWorkerCount: 2,
      asyncMaxPendingRequests: 8,
      asyncBackpressureMode: AsyncBackpressureMode.failFast,
    );
  final service = locator.service;

  try {
    final init = await service.initialize();
    if (init.isError()) {
      stderr.writeln('ODBC init failed: ${init.exceptionOrNull()}');
      exitCode = 1;
      return;
    }

    final connect = await service.connect(dsn);
    if (connect.isError()) {
      stderr.writeln('ODBC connect failed: ${connect.exceptionOrNull()}');
      exitCode = 1;
      return;
    }
    final connectionId = connect.getOrThrow().id;

    final results = <Map<String, Object?>>[];
    for (final scenario in scenarios) {
      if (scenario.encodingEnv != null) {
        dotenv.loadFromString(envString: 'ODBC_RESULT_ENCODING=${scenario.encodingEnv}');
      } else {
        dotenv.clean();
      }

      final executor = OdbcResultEncodingExecutor(
        service,
        usageProfile: scenario.profile ?? resolveOdbcUsageProfile(),
      );
      final encoding = resolveEffectiveOdbcResultEncoding(
        databaseType: DatabaseType.sqlServer,
        usageProfile: scenario.profile,
      );

      final samples = <int>[];
      for (var i = 0; i < iterations; i++) {
        final stopwatch = Stopwatch()..start();
        final result = await executor.execute(
          connectionId,
          OdbcPreparedQueryExecution(sql: sql, parameters: null),
          databaseType: DatabaseType.sqlServer,
        );
        stopwatch.stop();
        if (result.isError()) {
          stderr.writeln('Scenario ${scenario.name} failed: ${result.exceptionOrNull()}');
          exitCode = 1;
          return;
        }
        samples.add(stopwatch.elapsedMicroseconds);
      }

      samples.sort();
      final median = samples[samples.length ~/ 2];
      results.add({
        'scenario': scenario.name,
        'result_encoding': encoding.name,
        'iterations': iterations,
        'median_us': median,
        'min_us': samples.first,
        'max_us': samples.last,
      });
    }

    await service.disconnect(connectionId);

    if (jsonOutput) {
      print(jsonEncode({'sql': sql, 'scenarios': results}));
    } else {
      print('ODBC gateway encoding benchmark (sql: $sql)');
      for (final row in results) {
        print('  ${row['scenario']}: median ${row['median_us']} us (${row['result_encoding']})');
      }
    }
  } finally {
    locator.shutdown();
  }
}

String? _readArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}
