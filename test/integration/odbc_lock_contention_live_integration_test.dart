import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcConnectionStringAny;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final runLockContention = E2EEnv.get('ODBC_RUN_LOCK_CONTENTION_TESTS') == 'true';
  final skipUnlessDsn = !dsnValid
      ? 'Defina ODBC_TEST_DSN, ODBC_TEST_DSN_SQL_SERVER ou ODBC_TEST_DSN_POSTGRESQL no .env'
      : false;
  final skipUnlessOptIn = !runLockContention
      ? 'Defina ODBC_RUN_LOCK_CONTENTION_TESTS=true para rodar este teste de contenção/concorrência real.'
      : false;

  group('ODBC lock contention live integration', () {
    OdbcE2eRpcHarness? harness;
    OdbcE2eCoverageSql? sql;
    OdbcE2eSqlDialect? dialect;
    var isReady = false;

    setUpAll(() async {
      if (!dsnValid) {
        return;
      }
      final dsnValue = dsn;
      if (dsnValue.trim().isEmpty) {
        return;
      }
      final localDialect = detectOdbcE2eDialect(dsnValue);
      final opened = await OdbcE2eRpcHarness.open(dsnValue, localDialect);
      if (opened == null) {
        return;
      }
      harness = opened;
      dialect = localDialect;
      sql = OdbcE2eCoverageSql(localDialect);

      final drop = await opened.gateway.executeNonQuery(
        sql!.dropTableIfExists,
        null,
      );
      expect(drop.isSuccess(), isTrue, reason: 'drop table: $drop');

      final create = await opened.gateway.executeNonQuery(sql!.createTable, null);
      expect(create.isSuccess(), isTrue, reason: 'create table: $create');

      final seed = await opened.gateway.executeNonQuery(
        sql!.insertRow(
          id: 1,
          code: 'lock-row',
          amt: 10,
          birthDate: '2024-01-01',
          ts: '2024-01-01 00:00:00',
          isActive: true,
        ),
        null,
      );
      expect(seed.isSuccess(), isTrue, reason: 'seed row: $seed');
      isReady = true;
    });

    tearDownAll(() async {
      final h = harness;
      final localSql = sql;
      if (h == null || localSql == null) {
        return;
      }
      await h.gateway.executeNonQuery(localSql.dropTableIfExists, null);
      await h.shutdown();
    });

    test(
      'should handle lock contention with timeout without hanging pool',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final h = harness!;
        final localSql = sql!;
        final localDialect = dialect!;
        final service = h.locator.asyncService;

        final holderConnResult = await service.connect(h.connectionString);
        expect(holderConnResult.isSuccess(), isTrue, reason: '$holderConnResult');
        final holderConn = holderConnResult.getOrThrow();

        final beginResult = await service.beginTransaction(holderConn.id);
        expect(beginResult.isSuccess(), isTrue, reason: '$beginResult');
        final txId = beginResult.getOrThrow();

        try {
          final lockResult = await service.executeQuery(
            localSql.updateAmtById(1, 1),
            connectionId: holderConn.id,
          );
          expect(lockResult.isSuccess(), isTrue, reason: '$lockResult');

          final contenderSql = _contendedUpdateSql(
            dialect: localDialect,
            sql: localSql,
            rowId: 1,
            delta: 2,
            lockTimeoutMs: 250,
          );
          final contender = h.gateway.executeNonQuery(
            contenderSql,
            null,
            timeout: const Duration(milliseconds: 1200),
          );

          final result = await contender.timeout(const Duration(seconds: 30));
          expect(result.isError(), isTrue);
          final error = result.exceptionOrNull()!;
          expect(
            _matchesExpectedLockFailure(error, localDialect),
            isTrue,
            reason: '$error',
          );

          // Pool should remain usable after contention/cancel path.
          final healthyQuery = QueryRequest(
            id: 'after-contention-check',
            agentId: 'e2e-agent',
            query: localSql.selectIdCodeAmtById(1),
            timestamp: DateTime.now(),
          );
          final healthyResult = await h.gateway.executeQuery(healthyQuery);
          expect(healthyResult.isSuccess(), isTrue, reason: '$healthyResult');
        } finally {
          await service.rollbackTransaction(holderConn.id, txId);
          await service.disconnect(holderConn.id);
        }
      },
      skip: skipUnlessDsn != false ? skipUnlessDsn : skipUnlessOptIn,
    );

    test(
      'should sustain parallel smoke queries without stuck leases',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final h = harness!;
        final futures = List<Future<Result<QueryResponse>>>.generate(4, (index) {
          final request = QueryRequest(
            id: 'parallel-smoke-$index',
            agentId: 'e2e-agent',
            query: E2EEnv.odbcSmokeQuery,
            timestamp: DateTime.now(),
          );
          return h.gateway.executeQuery(request);
        });

        final results = await Future.wait(futures);
        for (final result in results) {
          expect(result.isSuccess(), isTrue, reason: '$result');
        }
      },
      skip: skipUnlessDsn != false ? skipUnlessDsn : skipUnlessOptIn,
    );
  });
}

String _contendedUpdateSql({
  required OdbcE2eSqlDialect dialect,
  required OdbcE2eCoverageSql sql,
  required int rowId,
  required double delta,
  required int lockTimeoutMs,
}) {
  final updateSql = sql.updateAmtById(rowId, delta);
  return switch (dialect) {
    OdbcE2eSqlDialect.sqlServer => 'SET LOCK_TIMEOUT $lockTimeoutMs; $updateSql',
    OdbcE2eSqlDialect.postgresql => "SET lock_timeout = '${lockTimeoutMs}ms'; $updateSql",
    OdbcE2eSqlDialect.sqlAnywhere => updateSql,
  };
}

bool _matchesExpectedLockFailure(Object error, OdbcE2eSqlDialect dialect) {
  final raw = error.toString().toLowerCase();
  final isTimeoutContext = error is domain.QueryExecutionFailure && error.context['timeout'] == true;
  final genericMatch = isTimeoutContext || raw.contains('timeout') || raw.contains('deadlock') || raw.contains('lock');
  if (genericMatch) {
    return true;
  }

  return switch (dialect) {
    OdbcE2eSqlDialect.sqlServer => raw.contains('1205') || raw.contains('1222'),
    OdbcE2eSqlDialect.postgresql => raw.contains('55p03') || raw.contains('40p01'),
    OdbcE2eSqlDialect.sqlAnywhere => raw.contains('-210') || raw.contains('-306'),
  };
}
