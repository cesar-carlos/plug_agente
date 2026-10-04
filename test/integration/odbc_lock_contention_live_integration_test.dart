import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

const _lockTimeout = Duration(milliseconds: 250);
const _contenderTimeout = Duration(milliseconds: 1200);

void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcConnectionStringAny;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final runLockContention = E2EEnv.odbcRunLockContentionTests;
  final skipUnlessDsn = !dsnValid
      ? 'Defina ODBC_TEST_DSN, ODBC_TEST_DSN_SQL_SERVER ou ODBC_TEST_DSN_POSTGRESQL no .env'
      : false;
  final skipUnlessOptIn = !runLockContention
      ? 'Defina ODBC_RUN_LOCK_CONTENTION_TESTS=true para rodar este teste de contenção/concorrência real.'
      : false;
  final skipLive = skipUnlessDsn != false ? skipUnlessDsn : skipUnlessOptIn;

  group('lock contention contract', () {
    final coverage = OdbcE2eCoverageSql(
      OdbcE2eSqlDialect.sqlServer,
      tableName: 'plug_agente_e2e_cov_lock',
    );

    test('should prefix SQL Server and PostgreSQL lock timeouts', () {
      expect(
        _contendedUpdateSql(
          dialect: OdbcE2eSqlDialect.sqlServer,
          sql: coverage,
          rowId: 1,
          delta: 2,
          lockTimeout: _lockTimeout,
        ),
        'SET LOCK_TIMEOUT ${_lockTimeout.inMilliseconds}; ${coverage.updateAmtById(1, 2)}',
      );

      final postgres = OdbcE2eCoverageSql(
        OdbcE2eSqlDialect.postgresql,
        tableName: 'plug_agente_e2e_cov_lock',
      );
      expect(
        _contendedUpdateSql(
          dialect: OdbcE2eSqlDialect.postgresql,
          sql: postgres,
          rowId: 1,
          delta: 2,
          lockTimeout: _lockTimeout,
        ),
        "SET lock_timeout = '${_lockTimeout.inMilliseconds}ms'; ${postgres.updateAmtById(1, 2)}",
      );
    });

    test('should keep the SQL Anywhere update as one statement', () {
      final anywhere = OdbcE2eCoverageSql(
        OdbcE2eSqlDialect.sqlAnywhere,
        tableName: 'plug_agente_e2e_cov_lock',
      );
      expect(
        _contendedUpdateSql(
          dialect: OdbcE2eSqlDialect.sqlAnywhere,
          sql: anywhere,
          rowId: 1,
          delta: 2,
          lockTimeout: _lockTimeout,
        ),
        anywhere.updateAmtById(1, 2),
      );
    });

    test('should apply SQL Anywhere blocking timeout on the connection string once', () {
      expect(
        sqlAnywhereLockContentionConnectionString(
          'Driver={SQL Anywhere 16};Server=db',
          _lockTimeout,
        ),
        'Driver={SQL Anywhere 16};Server=db;InitString={SET TEMPORARY OPTION blocking_timeout=${_lockTimeout.inMilliseconds}}',
      );
      expect(
        sqlAnywhereLockContentionConnectionString(
          'Driver={SQL Anywhere 16};Server=db;',
          _lockTimeout,
        ),
        'Driver={SQL Anywhere 16};Server=db;InitString={SET TEMPORARY OPTION blocking_timeout=${_lockTimeout.inMilliseconds}}',
      );

      const alreadyConfigured = 'Driver={SQL Anywhere 16};InitString={SET TEMPORARY OPTION blocking_timeout=1000}';
      expect(
        sqlAnywhereLockContentionConnectionString(alreadyConfigured, _lockTimeout),
        alreadyConfigured,
      );
    });

    test('should reject an unconfirmed client abort as a lock failure', () {
      final unconfirmed = domain.QueryExecutionFailure.withContext(
        message: 'Non-query execution timeout',
        context: const {
          'timeout': true,
          'outcome_unknown': true,
        },
      );
      expect(
        _matchesExpectedLockFailure(unconfirmed, OdbcE2eSqlDialect.sqlAnywhere),
        isFalse,
      );
      expect(
        _matchesExpectedLockFailure(
          domain.QueryExecutionFailure('Locked (SQLCODE=-210)'),
          OdbcE2eSqlDialect.sqlAnywhere,
        ),
        isTrue,
      );
    });
  });

  group('ODBC lock contention live integration', () {
    OdbcE2eRpcHarness? harness;
    OdbcE2eCoverageSql? sql;
    OdbcE2eSqlDialect? dialect;
    String? harnessDsn;
    var schemaCreated = false;
    var isReady = false;

    Future<OdbcE2eRpcHarness?> openHarness() {
      final localDialect = dialect;
      final localDsn = harnessDsn;
      if (localDialect == null || localDsn == null) {
        return Future<OdbcE2eRpcHarness?>.value();
      }
      return OdbcE2eRpcHarness.open(localDsn, localDialect);
    }

    setUpAll(() async {
      if (!dsnValid || !runLockContention) {
        return;
      }
      final dsnValue = dsn;
      final localDialect = detectOdbcE2eDialect(dsnValue);
      final localSql = OdbcE2eCoverageSql(
        localDialect,
        tableName: 'plug_agente_e2e_cov_lock',
      );
      dialect = localDialect;
      sql = localSql;
      harnessDsn = _harnessConnectionString(dsnValue, localDialect);

      final opened = await openHarness();
      if (opened == null) {
        return;
      }
      try {
        final drop = await opened.gateway.executeNonQuery(
          localSql.dropTableIfExists,
          null,
        );
        expect(drop.isSuccess(), isTrue, reason: 'drop table: $drop');

        final create = await opened.gateway.executeNonQuery(localSql.createTable, null);
        expect(create.isSuccess(), isTrue, reason: 'create table: $create');
        schemaCreated = true;

        final seed = await opened.gateway.executeNonQuery(
          localSql.insertRow(
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
      } finally {
        await opened.shutdown();
      }
    });

    setUp(() async {
      if (!isReady) {
        return;
      }
      harness = await openHarness();
    });

    tearDown(() async {
      final opened = harness;
      harness = null;
      if (opened == null) {
        return;
      }
      await opened.shutdown();
    });

    tearDownAll(() async {
      final localSql = sql;
      if (localSql == null || (!schemaCreated && !isReady)) {
        return;
      }
      final opened = await openHarness();
      if (opened == null) {
        return;
      }
      try {
        await opened.gateway.executeNonQuery(localSql.dropTableIfExists, null);
      } finally {
        await opened.shutdown();
      }
    });

    test(
      'should handle lock contention with timeout without hanging pool',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final h = harness;
        expect(h, isNotNull, reason: 'ODBC harness did not reopen after schema setup');
        final opened = h!;
        final localSql = sql!;
        final localDialect = dialect!;
        final service = opened.locator.asyncService;

        final holderConnResult = await service.connect(opened.connectionString);
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
            lockTimeout: _lockTimeout,
          );
          final contender = opened.gateway.executeNonQuery(
            contenderSql,
            null,
            timeout: _contenderTimeout,
          );

          final result = await contender.timeout(const Duration(seconds: 90));
          expect(result.isError(), isTrue);
          final error = result.exceptionOrNull()!;
          expect(
            _matchesExpectedLockFailure(error, localDialect),
            isTrue,
            reason: '$error',
          );
        } finally {
          await service.rollbackTransaction(holderConn.id, txId);
          await service.disconnect(holderConn.id);
        }

        final healthyQuery = QueryRequest(
          id: 'after-contention-check',
          agentId: 'e2e-agent',
          query: localSql.selectIdCodeAmtById(1),
          timestamp: DateTime.now(),
        );
        final healthyResult = await opened.gateway.executeQuery(healthyQuery);
        expect(healthyResult.isSuccess(), isTrue, reason: '$healthyResult');
        final activeAfterContention = await opened.connectionPool.getActiveCount();
        expect(activeAfterContention.isSuccess(), isTrue, reason: '$activeAfterContention');
        expect(activeAfterContention.getOrThrow(), 0);
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: skipLive,
      tags: const ['live', 'slow'],
    );

    test(
      'should sustain parallel smoke queries without stuck leases',
      () async {
        expect(isReady, isTrue, reason: 'ODBC init failed or DSN not configured');
        final h = harness;
        expect(h, isNotNull, reason: 'ODBC harness did not reopen after schema setup');
        final opened = h!;
        final futures = List<Future<Result<QueryResponse>>>.generate(4, (index) {
          final request = QueryRequest(
            id: 'parallel-smoke-$index',
            agentId: 'e2e-agent',
            query: E2EEnv.odbcSmokeQuery,
            timestamp: DateTime.now(),
          );
          return opened.gateway.executeQuery(request);
        });

        final results = await Future.wait(futures);
        for (final result in results) {
          expect(result.isSuccess(), isTrue, reason: '$result');
        }
        final activeAfterParallel = await opened.connectionPool.getActiveCount();
        expect(activeAfterParallel.isSuccess(), isTrue, reason: '$activeAfterParallel');
        expect(activeAfterParallel.getOrThrow(), 0);
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: skipLive,
      tags: const ['live'],
    );
  });
}

String _harnessConnectionString(String connectionString, OdbcE2eSqlDialect dialect) {
  if (dialect != OdbcE2eSqlDialect.sqlAnywhere) {
    return connectionString;
  }
  return sqlAnywhereLockContentionConnectionString(connectionString, _lockTimeout);
}

/// SQL Anywhere waits forever for a lock when `blocking_timeout` is 0.
/// The client deadline then aborts the statement as outcome-unknown, and the
/// lease pool quarantines that DSN. InitString applies the server wait on the
/// same connection that runs the update, before that deadline.
String sqlAnywhereLockContentionConnectionString(
  String connectionString,
  Duration lockTimeout,
) {
  if (connectionString.toLowerCase().contains('blocking_timeout')) {
    return connectionString;
  }
  final trimmed = connectionString.trimRight();
  final separator = trimmed.endsWith(';') ? '' : ';';
  return '$trimmed${separator}InitString={SET TEMPORARY OPTION blocking_timeout=${lockTimeout.inMilliseconds}}';
}

String _contendedUpdateSql({
  required OdbcE2eSqlDialect dialect,
  required OdbcE2eCoverageSql sql,
  required int rowId,
  required double delta,
  required Duration lockTimeout,
}) {
  final updateSql = sql.updateAmtById(rowId, delta);
  final lockTimeoutMs = lockTimeout.inMilliseconds;
  return switch (dialect) {
    OdbcE2eSqlDialect.sqlServer => 'SET LOCK_TIMEOUT $lockTimeoutMs; $updateSql',
    OdbcE2eSqlDialect.postgresql => "SET lock_timeout = '${lockTimeoutMs}ms'; $updateSql",
    OdbcE2eSqlDialect.sqlAnywhere => updateSql,
  };
}

bool _matchesExpectedLockFailure(Object error, OdbcE2eSqlDialect dialect) {
  if (error is domain.Failure && error.context['outcome_unknown'] == true) {
    return false;
  }
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
