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

typedef _Scenario = ({String name, OdbcUsageProfile? profile, String? encodingEnv});

Future<Map<String, Object?>?> runOdbcGatewayEncodingBenchmark({
  required String dsn,
  required String sql,
  int iterations = 6,
}) async {
  final scenarios = <_Scenario>[
    (name: 'balancedServer_rowMajor', profile: OdbcUsageProfile.balancedServer, encodingEnv: null),
    (name: 'highThroughput_columnar', profile: OdbcUsageProfile.highThroughput, encodingEnv: null),
    (name: 'explicit_columnarCompressed', profile: null, encodingEnv: 'columnarCompressed'),
  ];

  final results = <Map<String, Object?>>[];
  for (final scenario in scenarios) {
    if (_shouldSkipScenario(scenario)) {
      stderr.writeln('Skipping scenario ${scenario.name}: ODBC_GATEWAY_ENCODING_SKIP_${scenario.name}=1');
      continue;
    }

    final scenarioResult = await _runScenario(
      dsn: dsn,
      sql: sql,
      scenario: scenario,
      iterations: iterations,
    );
    if (scenarioResult == null) {
      continue;
    }
    results.add(scenarioResult);
  }

  if (results.isEmpty) {
    stderr.writeln('No gateway encoding scenarios executed.');
    return null;
  }

  return {'sql': sql, 'scenarios': results};
}

Future<Map<String, Object?>?> _runScenario({
  required String dsn,
  required String sql,
  required _Scenario scenario,
  required int iterations,
}) async {
  if (scenario.encodingEnv != null) {
    dotenv.loadFromString(envString: 'ODBC_RESULT_ENCODING=${scenario.encodingEnv}');
  } else {
    dotenv.clean();
  }

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
      stderr.writeln('ODBC init failed for ${scenario.name}: ${init.exceptionOrNull()}');
      return null;
    }

    final connect = await service.connect(dsn);
    if (connect.isError()) {
      stderr.writeln('ODBC connect failed for ${scenario.name}: ${connect.exceptionOrNull()}');
      return null;
    }
    final connectionId = connect.getOrThrow().id;

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
      try {
        final result = await executor.execute(
          connectionId,
          OdbcPreparedQueryExecution(sql: sql, parameters: null),
          databaseType: DatabaseType.sqlServer,
        );
        stopwatch.stop();
        if (result.isError()) {
          stderr.writeln('Scenario ${scenario.name} failed: ${result.exceptionOrNull()}');
          await service.disconnect(connectionId);
          return null;
        }
        samples.add(stopwatch.elapsedMicroseconds);
      } on Object catch (error) {
        stderr.writeln(
          'Scenario ${scenario.name} skipped after FFI lifecycle error: $error',
        );
        await service.disconnect(connectionId);
        return null;
      }
    }

    await service.disconnect(connectionId);
    samples.sort();
    return {
      'scenario': scenario.name,
      'result_encoding': encoding.name,
      'iterations': iterations,
      'median_us': samples[samples.length ~/ 2],
      'min_us': samples.first,
      'max_us': samples.last,
    };
  } finally {
    locator.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

bool _shouldSkipScenario(_Scenario scenario) {
  final globalSkip = Platform.environment['ODBC_GATEWAY_ENCODING_SKIP_COLUMNAR_COMPRESSED'];
  if (scenario.encodingEnv == 'columnarCompressed' &&
      (globalSkip == '1' || globalSkip == 'true')) {
    return true;
  }
  final key = 'ODBC_GATEWAY_ENCODING_SKIP_${scenario.name}';
  final raw = Platform.environment[key];
  return raw == '1' || raw == 'true';
}

Future<void> runOdbcGatewayEncodingBenchmarkCli(List<String> args) async {
  await AppEnvironment.loadOptional();

  final dsn = _readArg(args, '--dsn') ?? Platform.environment['ODBC_TEST_DSN'] ?? Platform.environment['ODBC_DSN'];
  if (dsn == null || dsn.trim().isEmpty) {
    stderr.writeln('Skipping: set ODBC_TEST_DSN / ODBC_DSN or pass --dsn');
    return;
  }

  final sql = _readArg(args, '--sql') ??
      Platform.environment['ODBC_BENCH_QUERY'] ??
      resolveDefaultOdbcBenchQuery(dsn: dsn);
  final iterations = int.tryParse(_readArg(args, '--iterations') ?? '6') ?? 6;
  final jsonOutput = args.contains('--json');

  final payload = await runOdbcGatewayEncodingBenchmark(
    dsn: dsn,
    sql: sql,
    iterations: iterations,
  );
  if (payload == null) {
    exitCode = 1;
    return;
  }

  if (jsonOutput) {
    print(jsonEncode(payload));
  } else {
    print('ODBC gateway encoding benchmark (sql: $sql)');
    for (final row in payload['scenarios']! as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      print('  ${map['scenario']}: median ${map['median_us']} us (${map['result_encoding']})');
    }
  }
}

String resolveDefaultOdbcBenchQuery({String? dsn}) {
  final explicit = Platform.environment['ODBC_BENCH_QUERY']?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }

  final normalized = (dsn ?? '').toLowerCase();
  if (normalized.contains('sql anywhere') || normalized.contains('sybase')) {
    return 'SELECT TOP 1000 table_id, table_name, creator, table_type FROM SYS.SYSTABLE';
  }
  return 'SELECT TOP 8000 object_id, name, type, type_desc, modify_date '
      'FROM sys.objects ORDER BY object_id';
}

String? _readArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}
