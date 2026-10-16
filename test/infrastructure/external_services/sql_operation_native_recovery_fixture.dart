import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

// Isolated crash fixture. Authorization is fixed test authority, not evidence of
// Client approval. The executor, native transaction, journal and transport are real.
class NativeRecoveryFixture implements ISqlOperationAuthorizer, ISqlOperationTransactionFactory {
  NativeRecoveryFixture(this.directory, this.phase, this.stage);
  final Directory directory;
  final String phase;
  final String stage;
  final locator = odbc.ServiceLocator();
  late odbc.OdbcService service;
  late Config config;
  late ISqlOperationTransactionFactory factory;
  late String observer;
  late String table;
  late String principal;
  int opened = 0;

  Future<void> initialize(String manifestPath, String engine) async {
    if (!['postgres', 'mssql', 'sybase'].contains(engine) ||
        !['before-commit', 'after-commit', 'in-flight-commit'].contains(stage)) {
      throw StateError('Explicit supported engine and crash stage required.');
    }
    final manifest = jsonDecode(await File(manifestPath).readAsString()) as Map<String, dynamic>;
    final runId = manifest['runId'] as String;
    final root = await Directory(manifest['root'] as String).resolveSymbolicLinks();
    if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(runId) ||
        Directory(root).parent.path != await Directory.systemTemp.resolveSymbolicLinks() ||
        !root.endsWith('${Platform.pathSeparator}$runId') ||
        File(manifestPath).parent.resolveSymbolicLinksSync() != root) {
      throw StateError('Only a private disposable fixture manifest is accepted.');
    }
    final engines = manifest['engines'] as Map<String, dynamic>;
    for (final required in ['postgres', 'mssql', 'sybase']) {
      if ((engines[required] as Map<String, dynamic>?)?['database'] != runId) {
        throw StateError('All three private engines are mandatory.');
      }
    }
    final fixture = engines[engine] as Map<String, dynamic>;
    config = Config(
      id: 'native-recovery',
      driverName: engine,
      odbcDriverName: engine,
      connectionString: fixture['connectionString'] as String,
      username: '',
      databaseName: runId,
      host: '127.0.0.1',
      port: fixture['port'] as int,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    locator.initialize(useAsync: true, asyncWorkerCount: 2);
    service = locator.asyncService;
    (await service.initialize()).getOrThrow();
    observer = (await service.connect(config.connectionString)).getOrThrow().id;
    final actual = await query(engine == 'postgres' ? 'SELECT CURRENT_DATABASE()' : 'SELECT DB_NAME()');
    expect(actual.rows.single.single, runId);
    final info = (await service.getConnectionDbmsInfo(observer)).getOrThrow();
    expect(info.engineId, {'postgres': 'postgres', 'mssql': 'sqlserver', 'sybase': 'sybase_asa'}[engine]);
    table = '${{'postgres': 'public', 'mssql': 'dbo', 'sybase': 'DBA'}[engine]}.recovery_fixture';
    principal = 'se7e_r_${sha256.convert(utf8.encode(directory.path)).toString().substring(0, 12)}';
    if (phase == 'crash') {
      await query('DROP TABLE IF EXISTS recovery_fixture');
      await query('CREATE TABLE recovery_fixture (name VARCHAR(64) NOT NULL)');
      await query('DROP TABLE IF EXISTS recovery_forbidden');
      await query('CREATE TABLE recovery_forbidden (name VARCHAR(64) NOT NULL)');
      final password = RegExp(
        '(?:^|;)PWD=([^;]+)',
        caseSensitive: false,
      ).firstMatch(config.connectionString)!.group(1)!;
      switch (engine) {
        case 'postgres':
          await query("CREATE ROLE $principal LOGIN PASSWORD '$password' NOSUPERUSER NOCREATEDB NOCREATEROLE");
          await query('GRANT CONNECT ON DATABASE "$runId" TO $principal');
          await query('GRANT USAGE ON SCHEMA public TO $principal');
          await query('GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_system() TO $principal');
        case 'mssql':
          await query("CREATE LOGIN $principal WITH PASSWORD = '$password', CHECK_POLICY = OFF");
          await query('CREATE USER $principal FOR LOGIN $principal');
        case 'sybase':
          await query('CREATE USER $principal IDENTIFIED BY "$password"');
          await query('GRANT SELECT ON DBA.se7e_source_identity TO $principal');
      }
      await query('GRANT SELECT, INSERT ON $table TO $principal');
    }
    final enrolled = await OdbcSourceDiscovery.inspectConnection(service, observer, config, runId);
    config = config.copyWith(
      connectionString: config.connectionString.replaceFirstMapped(
        RegExp('(^|;)UID=[^;]+', caseSensitive: false),
        (match) => '${match[1]}UID=$principal',
      ),
    );
    final reader = (await service.connect(config.connectionString)).getOrThrow().id;
    try {
      final proof = await OdbcSourceDiscovery.inspectConnection(service, reader, config, runId);
      expect(proof.identityHash, enrolled.identityHash);
      expect(
        (await service.executeQuery(
          engine == 'sybase' ? 'SELECT CURRENT USER' : 'SELECT CURRENT_USER',
          connectionId: reader,
        )).getOrThrow().rows.single.single.toString().trim().toLowerCase(),
        principal,
      );
      final forbidden = '${table.split('.').first}.recovery_forbidden';
      for (final sql in [
        'SELECT * FROM $forbidden',
        "INSERT INTO $forbidden(name) VALUES ('forbidden')",
        "UPDATE $table SET name='forbidden'",
        'DELETE FROM $table',
        'ALTER TABLE $table ADD forbidden INTEGER',
        'DROP TABLE $table',
      ]) {
        expect(
          (await service.executeQuery(sql, connectionId: reader)).isError(),
          isTrue,
          reason: 'Restricted native principal must not access unrelated data or DDL.',
        );
      }
    } finally {
      (await service.disconnect(reader)).getOrThrow();
    }
    final proxy = Platform.environment['PLUG_SQL_OPERATION_NATIVE_PROXY_PORT'];
    if (proxy != null) {
      final port = int.parse(proxy);
      if (port < 1 || port > 65535 || stage != 'in-flight-commit') throw StateError('Invalid private commit proxy.');
      final connection = switch (engine) {
        'postgres' => '${config.connectionString};SERVER=127.0.0.1;PORT=$port',
        'mssql' => config.connectionString.replaceFirst(
          RegExp('SERVER=[^;]+', caseSensitive: false),
          'SERVER=127.0.0.1,$port',
        ),
        _ => config.connectionString.replaceFirst(RegExp('HOST=[^;]+', caseSensitive: false), 'HOST=127.0.0.1:$port'),
      };
      config = config.copyWith(connectionString: connection);
    }
    factory = OdbcSqlOperationTransactionFactory(
      service,
      ConfigService(ConfigValidator()),
      DirectOdbcConnectionLimiter(maxConcurrent: 1, acquireTimeout: const Duration(seconds: 5)),
    );
  }

  Future<odbc.QueryResult> query(String sql) async =>
      (await service.executeQuery(sql, connectionId: observer)).getOrThrow();

  @override
  Future<Result<SqlOperationTarget>> authorize(
    SqlOperationReference reference,
    String token,
    String agentId,
    List<SqlOperationStep> steps,
  ) async {
    expect(reference.database, config.databaseName);
    expect(token, 'token');
    expect(agentId, 'agent-operation-test');
    return Success(
      SqlOperationTarget(
        config: config,
        database: reference.database,
        scopeHash: 'a' * 64,
        authorizationHash: 'native-recovery-fixture',
      ),
    );
  }

  @override
  Future<Result<ISqlOperationTransaction>> open(
    SqlOperationTarget target,
    Duration timeout, {
    SqlOperationPlan? plan,
  }) async {
    opened++;
    final result = await factory.open(target, timeout, plan: plan);
    if (result.isError()) return result;
    return Success(_CrashTransaction(result.getOrThrow(), this));
  }

  Future<Never> crash() async {
    await File('${directory.path}/interrupted-after-step').writeAsString(stage, flush: true);
    exit(73);
  }

  Future<void> verifyRecovery() async {
    expect(opened, 0, reason: 'Recovered requests must never reopen a native transaction.');
    final rows = (await query('SELECT name FROM $table')).rows;
    expect(
      rows,
      stage != 'before-commit'
          ? [
              ['fixture'],
            ]
          : isEmpty,
    );
    await query('REVOKE INSERT ON $table FROM $principal');
    final reader = (await service.connect(config.connectionString)).getOrThrow().id;
    try {
      expect(
        (await service.executeQuery("INSERT INTO $table(name) VALUES ('forbidden')", connectionId: reader)).isError(),
        isTrue,
      );
    } finally {
      (await service.disconnect(reader)).getOrThrow();
    }
    expect((await query('SELECT name FROM $table')).rows, rows);
    await File('${directory.path}/native-recovery-evidence.json').writeAsString(
      jsonEncode({'stage': stage, 'rows': rows.length, 'replayedTransactions': opened}),
      flush: true,
    );
  }

  Future<void> close() async {
    (await service.disconnect(observer)).getOrThrow();
    locator.shutdown();
  }
}

class _CrashTransaction implements ISqlOperationTransaction {
  const _CrashTransaction(this.delegate, this.fixture);
  final ISqlOperationTransaction delegate;
  final NativeRecoveryFixture fixture;
  @override
  Result<void> validatePlan(SqlOperationPlan plan) => delegate.validatePlan(plan);
  @override
  Future<Result<SqlOperationStepResult>> execute(
    SqlOperationStep step,
    Map<String, SqlScalar> parameters,
    Duration timeout,
  ) async {
    final result = await delegate.execute(step, parameters, timeout);
    if (result.isSuccess() && fixture.stage == 'before-commit') await fixture.crash();
    return result;
  }

  @override
  Future<Result<void>> commit(Duration timeout) async {
    if (fixture.stage == 'in-flight-commit') {
      await File('${fixture.directory.path}/commit-ready').writeAsString('ready', flush: true);
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!File('${fixture.directory.path}/commit-go').existsSync()) {
        if (DateTime.now().isAfter(deadline)) throw StateError('Native commit controller did not arm.');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    final result = await delegate.commit(timeout);
    if (fixture.stage == 'in-flight-commit') {
      await File('${fixture.directory.path}/commit-returned').writeAsString('returned', flush: true);
    }
    if (result.isSuccess() && fixture.stage == 'after-commit') await fixture.crash();
    return result;
  }

  @override
  Future<Result<void>> rollback(Duration timeout) => delegate.rollback(timeout);
  @override
  Future<Result<void>> close() => delegate.close();
}
