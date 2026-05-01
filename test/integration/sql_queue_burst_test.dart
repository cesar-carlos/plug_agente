import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

const _burstQueueSize = 20;
const _burstWorkers = 4;
const _burstRequestCount = 50;

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
        maxQueueSize: _burstQueueSize,
        maxConcurrentWorkers: _burstWorkers,
        metricsCollector: localHarness.metrics,
        defaultEnqueueTimeout: const Duration(seconds: 30),
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

        try {
          final futures = List.generate(_burstRequestCount, (index) {
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
        } finally {
          queuedGateway.dispose();
        }
      },
      skip: skipUnlessDsn != false
          ? skipUnlessDsn
          : skipUnlessOptIn != false
          ? skipUnlessOptIn
          : skipUnlessSlowQuery,
    );

    test(
      'should recover and serve normal traffic after an overflow burst',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final localHarness = harness!;
        final burstQuery = slowQuery ?? '';
        final queuedGateway = createQueuedGateway();

        try {
          final burst = List.generate(_burstRequestCount, (index) {
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
        } finally {
          queuedGateway.dispose();
        }
      },
      skip: skipUnlessDsn != false
          ? skipUnlessDsn
          : skipUnlessOptIn != false
          ? skipUnlessOptIn
          : skipUnlessSlowQuery,
    );
  });
}
