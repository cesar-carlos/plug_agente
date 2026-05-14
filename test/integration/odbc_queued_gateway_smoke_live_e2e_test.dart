import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:result_dart/result_dart.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final skipUnlessDsn = !dsnValid
      ? 'Defina ODBC_E2E_RPC_DSN ou pelo menos um de ODBC_TEST_DSN / ODBC_DSN, '
            'ODBC_TEST_DSN_SQL_SERVER, ODBC_TEST_DSN_POSTGRESQL no .env.'
      : false;

  group('ODBC queued gateway smoke (E2E)', () {
    OdbcE2eRpcHarness? harness;
    QueuedDatabaseGateway? queuedGateway;

    setUpAll(() async {
      if (!dsnValid) {
        return;
      }
      final connectionString = dsn;
      final opened = await OdbcE2eRpcHarness.open(
        connectionString,
        detectOdbcE2eDialect(connectionString),
      );
      if (opened == null) {
        return;
      }
      harness = opened;
      queuedGateway = QueuedDatabaseGateway(
        delegate: opened.gateway,
        queue: SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 2,
          metricsCollector: opened.metrics,
        ),
      );
    });

    tearDownAll(() async {
      queuedGateway?.dispose();
      await harness?.shutdown();
    });

    test(
      'should execute parallel smoke queries without leaking pooled leases',
      () async {
        final h = harness;
        final gateway = queuedGateway;
        expect(h, isNotNull, reason: 'ODBC init failed or DSN not configured');
        expect(gateway, isNotNull, reason: 'ODBC init failed or DSN not configured');

        final results = await Future.wait(
          List<Future<Result<QueryResponse>>>.generate(4, (index) {
            return gateway!.executeQuery(
              QueryRequest(
                id: 'queued-smoke-$index',
                agentId: 'e2e-agent',
                query: E2EEnv.odbcSmokeQuery,
                timestamp: DateTime.now(),
              ),
            );
          }),
        );

        expect(results.every((result) => result.isSuccess()), isTrue);
        final activeCount = await h!.connectionPool.getActiveCount(
          connectionString: h.connectionString,
        );
        expect(activeCount.getOrThrow(), equals(0));
      },
      skip: skipUnlessDsn,
      tags: const ['live'],
    );
  });
}
