import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/external_services/homogeneous_insert_batch_planner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../helpers/mock_odbc_connection_settings.dart';

class _BenchmarkOdbcService extends Mock implements OdbcService {}

class _BenchmarkConnectionPool extends Mock implements IConnectionPool {}

void main() {
  test(
    'emits ODBC hot-path benchmark samples',
    () async {
      registerFallbackValue(const ConnectionOptions());
      registerFallbackValue(const StatementOptions());
      registerFallbackValue(const ConnectionAcquireOptions());
      final metrics = MetricsCollector();
      addTearDown(metrics.dispose);
      for (var index = 0; index < 256; index++) {
        metrics.recordQueueWaitTime(Duration(microseconds: index + 1));
      }
      final rows = List<Map<String, dynamic>>.generate(
        257,
        (index) => <String, dynamic>{'id': index, 'name': 'row-$index'},
        growable: false,
      );
      const pagination = QueryPaginationRequest(
        page: 1,
        pageSize: 256,
        queryHash: 'benchmark',
      );
      final commands = List<SqlCommand>.generate(
        100,
        (index) => SqlCommand(
          sql:
              'INSERT INTO benchmark_rows (id, amount, name) VALUES '
              "($index, ${index + 0.5}, 'row-$index')",
        ),
        growable: false,
      );

      final scenarios = <Map<String, Object>>[
        _measure('health_snapshot', metrics.getSnapshot, payloadBytes: 0),
        _measure(
          'pagination_materialization',
          () => OdbcGatewayQueryResultMapper.materializePagination(
            pagination,
            rows,
          ),
          payloadBytes: rows.length * 2 * 8,
        ),
        _measure(
          'bulk_insert_planning',
          () => HomogeneousInsertBatchPlanner.tryPlan(commands),
          payloadBytes: commands.length * 3 * 8,
        ),
      ];
      scenarios.add(
        await _measureAsync('read_only_batch_worker_warmup', () async {
          final service = _BenchmarkOdbcService();
          final pool = _BenchmarkConnectionPool();
          when(() => pool.acquire('DSN=benchmark', options: any(named: 'options'))).thenAnswer(
            (_) async => const Success('worker'),
          );
          when(() => pool.release('worker')).thenAnswer(
            (_) async => const Success(unit),
          );
          final manager = OdbcGatewayConnectionManager(
            service: service,
            connectionPool: pool,
            directConnectionLimiter: DirectOdbcConnectionLimiter(
              maxConcurrent: 2,
              acquireTimeout: const Duration(seconds: 1),
            ),
            metrics: metrics,
          );
          final executor = OdbcReadOnlyBatchParallelExecutor(
            connectionManager: manager,
            queryRunner: OdbcQueryRunner(
              queries: service,
              metrics: metrics,
              statementExecutor: OdbcStatementExecutor(
                service: service,
                metrics: metrics,
                markConnectionForDiscard: manager.markConnectionForDiscard,
              ),
              resultEncodingExecutor: OdbcResultEncodingExecutor(service),
              markConnectionForDiscard: manager.markConnectionForDiscard,
            ),
            optionsResolver: OdbcConnectionOptionsResolver(
              MockOdbcConnectionSettings(poolSize: 4),
            ),
            metrics: metrics,
            parallelSemaphore: PoolSemaphore(2),
            uuid: const Uuid(),
            recordInfrastructureFailure: ({required originalSql, required errorMessage, rpcRequestId}) {},
          );
          final result = await executor.execute(
            agentId: 'benchmark',
            commands: const <SqlCommand>[],
            connectionString: 'DSN=benchmark',
            databaseConfig: DatabaseConfig.sqlServer(
              driverName: 'driver',
              username: 'user',
              password: 'password',
              database: 'database',
              server: 'localhost',
              port: 1433,
            ),
            options: const SqlExecutionOptions(maxParallelReadOnlyBatchItems: 2),
            timeout: const Duration(seconds: 1),
            batchSqlPreview: '',
            poolSize: 4,
          );
          expect(result.isSuccess(), isTrue);
        }, payloadBytes: 0),
      );
      final payload = <String, Object>{
        'benchmark': 'odbc_hot_paths',
        'scenarios': scenarios,
      };
      stdout.writeln(jsonEncode(payload));
      expect(scenarios, hasLength(4));
    },
    tags: const ['perf'],
  );
}

Future<Map<String, Object>> _measureAsync(
  String scenario,
  Future<void> Function() operation, {
  required int payloadBytes,
}) async {
  const iterations = 30;
  final samples = <int>[];
  for (var index = 0; index < iterations; index++) {
    final stopwatch = Stopwatch()..start();
    await operation();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  return {
    'scenario': scenario,
    'iterations': iterations,
    'p50_us': samples[(samples.length * 0.50).floor()],
    'p95_us': samples[(samples.length * 0.95).floor()],
    'p99_us': samples[(samples.length * 0.99).floor()],
    'input_payload_bytes': payloadBytes,
  };
}

Map<String, Object> _measure(
  String scenario,
  Object? Function() operation, {
  required int payloadBytes,
}) {
  const iterations = 100;
  final samples = <int>[];
  for (var index = 0; index < iterations; index++) {
    final stopwatch = Stopwatch()..start();
    operation();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  return {
    'scenario': scenario,
    'iterations': iterations,
    'p50_us': samples[(samples.length * 0.50).floor()],
    'p95_us': samples[(samples.length * 0.95).floor()],
    'p99_us': samples[(samples.length * 0.99).floor()],
    // Stable allocation-pressure proxy: bytes entering the hot path, not a VM
    // heap measurement (which Dart does not expose portably in production).
    'input_payload_bytes': payloadBytes,
  };
}
