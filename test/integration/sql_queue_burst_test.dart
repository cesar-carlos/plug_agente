import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final runBurstTests = E2EEnv.odbcRunBurstTests;
  final slowQuery = E2EEnv.odbcLongQuery;
  final slowQueryValid = slowQuery != null && slowQuery.trim().isNotEmpty;
  const burstWorkerHold = Duration(milliseconds: 750);

  final skipUnlessDsn = !dsnValid ? 'Defina ODBC_E2E_RPC_DSN ou uma DSN ODBC de teste no .env.' : false;
  final skipUnlessOptIn = !runBurstTests
      ? 'Defina RUN_ODBC_BURST_TESTS=true para rodar os testes opt-in de burst.'
      : false;
  final skipUnlessSlowQuery = !slowQueryValid
      ? 'Defina ODBC_INTEGRATION_LONG_QUERY (ou variante por banco) para forcar saturacao deterministica da fila.'
      : false;

  group('SQL queue burst live integration', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;

    setUpAll(() async {
      if (!dsnValid || !runBurstTests || !slowQueryValid) {
        return;
      }

      final localDsn = dsn.trim();
      final dialect = detectOdbcE2eDialect(localDsn);
      harness = await OdbcE2eRpcHarness.open(localDsn, dialect);
      isReady = harness != null;
    });

    tearDownAll(() async {
      final localHarness = harness;
      if (localHarness != null) {
        await localHarness.shutdown();
      }
    });

    QueuedDatabaseGateway createQueuedGateway({
      int? maxQueueSize,
      int? maxConcurrentWorkers,
    }) {
      final localHarness = harness!;
      localHarness.metrics.clear();
      final queue = SqlExecutionQueue(
        maxQueueSize: maxQueueSize ?? E2EEnv.odbcBurstQueueSize,
        maxConcurrentWorkers: maxConcurrentWorkers ?? E2EEnv.odbcBurstWorkers,
        metricsCollector: localHarness.metrics,
        defaultEnqueueTimeout: Duration(
          milliseconds: E2EEnv.odbcBurstEnqueueTimeoutMs,
        ),
      );
      return QueuedDatabaseGateway(
        delegate: _DelayedQueryGateway(
          localHarness.gateway,
          queryDelay: burstWorkerHold,
        ),
        queue: queue,
      );
    }

    QueryRequest buildRequest(String id, String sql) {
      return QueryRequest(
        id: id,
        agentId: 'e2e-agent',
        query: sql,
        timestamp: DateTime.now(),
      );
    }

    Future<void> waitForQueueToFill(QueuedDatabaseGateway gateway) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        if (gateway.queueSize >= gateway.maxQueueSize) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    Future<void> writeHealthSnapshot(
      QueuedDatabaseGateway gateway,
      String name,
    ) async {
      final outputDirectory = Platform.environment['ODBC_BURST_HEALTH_SNAPSHOT_DIR']?.trim();
      if (outputDirectory == null || outputDirectory.isEmpty) {
        return;
      }

      final localHarness = harness!;
      final healthService = HealthService(
        metricsCollector: localHarness.metrics,
        gateway: gateway,
        connectionPool: localHarness.connectionPool,
      );
      final snapshot = await healthService.getHealthStatusAsync();
      final file = File('$outputDirectory${Platform.pathSeparator}health_$name.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(snapshot)}\n');
    }

    test(
      'should reject a controlled burst without leaking pooled connections',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final localHarness = harness!;
        final burstQuery = slowQuery ?? '';
        final queuedGateway = createQueuedGateway(
          maxQueueSize: 2,
          maxConcurrentWorkers: 1,
        );
        final elapsed = Stopwatch()..start();

        try {
          await writeHealthSnapshot(queuedGateway, 'burst_overflow_before');
          final primingCount = math.min(
            E2EEnv.odbcBurstRequestCount - 1,
            queuedGateway.maxWorkers + queuedGateway.maxQueueSize,
          );
          final primingFutures = <Future<Result<QueryResponse>>>[];
          for (var index = 0; index < primingCount; index++) {
            primingFutures.add(
              queuedGateway.executeQuery(
                buildRequest('burst-prime-$index', burstQuery),
              ),
            );
          }

          await waitForQueueToFill(queuedGateway);
          final queueSizeBeforeOverflow = queuedGateway.queueSize;
          final activeWorkersBeforeOverflow = queuedGateway.activeWorkers;

          final overflowCount = math.max(
            1,
            E2EEnv.odbcBurstRequestCount - primingCount,
          );
          final overflowResults = await Future.wait(
            List.generate(overflowCount, (index) {
              return queuedGateway.executeQuery(
                buildRequest('burst-overflow-$index', burstQuery),
              );
            }),
          );
          final primingResults = await Future.wait(primingFutures);
          final results = <Result<QueryResponse>>[
            ...overflowResults,
            ...primingResults,
          ];
          final rejected = results.where((result) {
            final error = result.exceptionOrNull();
            return error is domain.ConfigurationFailure && error.context['reason'] == 'sql_queue_full';
          }).length;
          final succeeded = results.where((result) => result.isSuccess()).length;
          final accepted = results.length - rejected;

          expect(
            rejected,
            greaterThan(0),
            reason:
                'queueSizeBeforeOverflow=$queueSizeBeforeOverflow, '
                'activeWorkersBeforeOverflow=$activeWorkersBeforeOverflow, '
                'maxQueueSize=${queuedGateway.maxQueueSize}, '
                'maxWorkers=${queuedGateway.maxWorkers}, '
                'overflowCount=$overflowCount, '
                'accepted=$accepted, '
                'succeeded=$succeeded',
          );
          expect(accepted, greaterThan(0));

          final active = await localHarness.connectionPool.getActiveCount();
          expect(active.isSuccess(), isTrue, reason: '$active');
          expect(active.getOrThrow(), 0);
          elapsed.stop();
          final maxMs = E2EEnv.odbcBurstMaxMsPerTest;
          developer.log(
            'E2E_SQL_QUEUE_BURST_TIMING '
            '${jsonEncode({
              'test': 'overflow',
              'elapsed_ms': elapsed.elapsedMilliseconds,
              'request_count': E2EEnv.odbcBurstRequestCount,
              'queue_size': queuedGateway.maxQueueSize,
              'workers': queuedGateway.maxWorkers,
              'rejected': rejected,
              'accepted': accepted,
              'succeeded': succeeded,
            })}',
            name: 'e2e.sql_queue_burst',
          );
          expect(
            elapsed.elapsedMilliseconds,
            lessThanOrEqualTo(maxMs),
            reason: 'burst overflow test exceeded ODBC_BURST_MAX_MS_PER_TEST=$maxMs',
          );
        } finally {
          await writeHealthSnapshot(queuedGateway, 'burst_overflow_after');
          queuedGateway.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
      skip: skipUnlessDsn != false
          ? skipUnlessDsn
          : skipUnlessOptIn != false
          ? skipUnlessOptIn
          : skipUnlessSlowQuery,
      tags: const ['live', 'slow'],
    );

    test(
      'should recover and serve normal traffic after an overflow burst',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final localHarness = harness!;
        final burstQuery = slowQuery ?? '';
        final queuedGateway = createQueuedGateway();
        final elapsed = Stopwatch()..start();

        try {
          await writeHealthSnapshot(queuedGateway, 'burst_recovery_before');
          final burst = List.generate(E2EEnv.odbcBurstRequestCount, (index) {
            return queuedGateway.executeQuery(
              buildRequest('burst-recovery-$index', burstQuery),
            );
          });
          await Future.wait(burst);

          final smokeResults = await Future.wait(
            List.generate(5, (index) {
              return queuedGateway.executeQuery(
                buildRequest('recovery-$index', E2EEnv.odbcSmokeQuery),
              );
            }),
          );

          for (final result in smokeResults) {
            expect(result.isSuccess(), isTrue, reason: '$result');
          }

          final active = await localHarness.connectionPool.getActiveCount();
          expect(active.isSuccess(), isTrue, reason: '$active');
          expect(active.getOrThrow(), 0);
          elapsed.stop();
          final maxMs = E2EEnv.odbcBurstMaxMsPerTest;
          developer.log(
            'E2E_SQL_QUEUE_BURST_TIMING '
            '${jsonEncode({
              'test': 'recovery',
              'elapsed_ms': elapsed.elapsedMilliseconds,
              'request_count': E2EEnv.odbcBurstRequestCount,
              'queue_size': E2EEnv.odbcBurstQueueSize,
              'workers': E2EEnv.odbcBurstWorkers,
            })}',
            name: 'e2e.sql_queue_burst',
          );
          expect(
            elapsed.elapsedMilliseconds,
            lessThanOrEqualTo(maxMs),
            reason: 'burst recovery test exceeded ODBC_BURST_MAX_MS_PER_TEST=$maxMs',
          );
        } finally {
          await writeHealthSnapshot(queuedGateway, 'burst_recovery_after');
          queuedGateway.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
      skip: skipUnlessDsn != false
          ? skipUnlessDsn
          : skipUnlessOptIn != false
          ? skipUnlessOptIn
          : skipUnlessSlowQuery,
      tags: const ['live', 'slow'],
    );
  });
}

final class _DelayedQueryGateway implements IDatabaseGateway {
  const _DelayedQueryGateway(
    this._delegate, {
    required this.queryDelay,
  });

  final IDatabaseGateway _delegate;
  final Duration queryDelay;

  @override
  Future<Result<bool>> testConnection(String connectionString) {
    return _delegate.testConnection(connectionString);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
  }) async {
    await Future<void>.delayed(queryDelay);
    return _delegate.executeQuery(
      request,
      timeout: timeout,
      database: database,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
  }) {
    return _delegate.executeBatch(
      agentId,
      commands,
      database: database,
      options: options,
      timeout: timeout,
      sourceRpcRequestId: sourceRpcRequestId,
    );
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  }) {
    return _delegate.executeNonQuery(
      query,
      parameters,
      timeout: timeout,
      database: database,
    );
  }

  @override
  Future<Result<int>> executeBulkInsert(
    BulkInsertRequest request, {
    Duration? timeout,
    String? database,
  }) {
    return _delegate.executeBulkInsert(
      request,
      timeout: timeout,
      database: database,
    );
  }
}
