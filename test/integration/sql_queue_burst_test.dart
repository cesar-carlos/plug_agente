import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

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

    QueuedDatabaseGateway createQueuedGateway() {
      final localHarness = harness!;
      localHarness.metrics.clear();
      final queue = SqlExecutionQueue(
        maxQueueSize: E2EEnv.odbcBurstQueueSize,
        maxConcurrentWorkers: E2EEnv.odbcBurstWorkers,
        metricsCollector: localHarness.metrics,
        defaultEnqueueTimeout: Duration(
          milliseconds: E2EEnv.odbcBurstEnqueueTimeoutMs,
        ),
      );
      return QueuedDatabaseGateway(
        delegate: localHarness.gateway,
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

    test(
      'should reject a controlled burst without leaking pooled connections',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final localHarness = harness!;
        final burstQuery = slowQuery ?? '';
        final queuedGateway = createQueuedGateway();
        final elapsed = Stopwatch()..start();

        try {
          final futures = List.generate(E2EEnv.odbcBurstRequestCount, (index) {
            return queuedGateway.executeQuery(
              buildRequest('burst-$index', burstQuery),
            );
          });

          final results = await Future.wait(futures);
          final rejected = results.where((result) {
            final error = result.exceptionOrNull();
            return error is domain.ConfigurationFailure && error.context['reason'] == 'sql_queue_full';
          }).length;
          final succeeded = results.where((result) => result.isSuccess()).length;

          expect(rejected, greaterThan(0));
          expect(succeeded, greaterThan(0));
          expect(
            localHarness.metrics.sqlQueueRejectionCount,
            greaterThanOrEqualTo(rejected),
          );

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
              'queue_size': E2EEnv.odbcBurstQueueSize,
              'workers': E2EEnv.odbcBurstWorkers,
              'rejected': rejected,
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
