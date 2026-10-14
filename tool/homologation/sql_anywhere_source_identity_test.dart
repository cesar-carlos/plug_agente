import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_verified_query.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';

// Explicit, isolated agent-driver test. Never reads .env or operational configuration.
void main() {
  final path = Platform.environment['PERSONA_SQL_ANYWHERE_FIXTURE'];
  if (path == null) throw StateError('PERSONA_SQL_ANYWHERE_FIXTURE is required');
  final fixture = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final runId = fixture['runId'] as String;
  final root = Directory(fixture['root'] as String).resolveSymbolicLinksSync();
  if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(runId) ||
      !root.endsWith('${Platform.pathSeparator}$runId')) {
    throw StateError('Only an isolated, explicitly named fixture is accepted');
  }
  final phase = fixture['phase'] as String;
  if (!['missing', 'enroll', 'restart', 'restore', 'replacement'].contains(phase)) {
    throw StateError('Unknown fixture phase');
  }
  final config = Config(
    id: runId,
    driverName: 'sybase',
    odbcDriverName: 'SQL Anywhere 16',
    connectionString: fixture['connectionString'] as String,
    username: '',
    databaseName: runId,
    host: '127.0.0.1',
    port: fixture['port'] as int,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  late odbc.ServiceLocator locator;
  late odbc.OdbcService service;
  late String id;
  final limiter = DirectOdbcConnectionLimiter(maxConcurrent: 2, acquireTimeout: const Duration(seconds: 5));
  late OdbcSourceDiscovery probe;
  final enrolled = File('$root${Platform.pathSeparator}enrolled-identity.json');
  setUpAll(() async {
    locator = odbc.ServiceLocator()..initialize(useAsync: true, asyncWorkerCount: 2);
    service = locator.asyncService;
    (await service.initialize()).getOrThrow();
    id = (await service.connect(config.connectionString)).getOrThrow().id;
    probe = OdbcSourceDiscovery(service, _Strings(), limiter);
  });
  tearDownAll(() async {
    await service.disconnect(id);
    locator.shutdown();
  });
  Future<odbc.QueryResult> sql(String text) async => (await service.executeQuery(text, connectionId: id)).getOrThrow();
  Future<ExpectedSource> current() async {
    final proof = await OdbcSourceDiscovery.inspectConnection(service, id, config, runId);
    expect(proof.identityKind, 'provisioned');
    expect(proof.dialect, 'sybase');
    return ExpectedSource(dialect: proof.dialect, identityHash: proof.identityHash);
  }

  Future<void> read(ExpectedSource expected, {bool denied = false}) async {
    final result = await OdbcVerifiedQuery(probe).execute(
      QueryRequest(
        id: 'fixture',
        agentId: 'fixture',
        query: denied ? 'SELECT nonexistent_column FROM nonexistent_table' : 'SELECT 17 AS answer',
        timestamp: DateTime.now(),
        sqlHandlingMode: SqlHandlingMode.preserve,
        expectedSource: expected,
      ),
      config,
      runId,
      const Duration(seconds: 15),
    );
    if (denied) {
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull().toString(), contains('Executing connection does not match'));
    } else {
      expect(result.getOrThrow().data, [
        {'answer': 17},
      ]);
    }
  }

  if (phase == 'missing') {
    test('unprovisioned database fails closed without creating any marker', () async {
      expect((await probe.inspect(config, runId)).isError(), isTrue);
      expect(
        (await sql("SELECT COUNT(*) FROM SYS.SYSTABLE WHERE table_name='se7e_source_identity'")).rows.single.single,
        0,
      );
    });
    return;
  }
  if (phase == 'restart' || phase == 'restore' || phase == 'replacement') {
    test('durable identity $phase on the actual connection', () async {
      final expected = ExpectedSource.fromJson(jsonDecode(enrolled.readAsStringSync()));
      final actual = await current();
      expect(actual.identityHash == expected.identityHash, phase != 'replacement');
      await read(expected, denied: phase == 'replacement');
    });
    return;
  }
  test('enrollment survives fresh connections and records no native identifiers', () async {
    final expected = await current();
    final fresh = (await probe.inspect(config, runId)).getOrThrow();
    expect(fresh.identityHash, expected.identityHash);
    enrolled.writeAsStringSync(jsonEncode(expected.toJson()), flush: true);
  });
  test('verified SELECT succeeds; stale UUID rejects before business SQL', () async {
    await read(await current());
    await read(ExpectedSource(dialect: 'sybase', identityHash: '0' * 64), denied: true);
  });
  test('DBA provisioned marker refuses INSERT UPDATE DELETE, preserving the UUID', () async {
    final before = await current();
    for (final statement in [
      'UPDATE DBA.se7e_source_identity SET version=1 WHERE singleton=1',
      'DELETE FROM DBA.se7e_source_identity WHERE singleton=1',
      "INSERT INTO DBA.se7e_source_identity VALUES(1,1,'11111111-1111-4111-8111-111111111111')",
    ]) {
      expect((await service.executeQuery(statement, connectionId: id)).isError(), isTrue);
    }
    expect((await current()).identityHash, before.identityHash);
  });
  test('principal with SELECT only proves identity; missing grant fails closed', () async {
    await sql('CREATE USER se7e_reader IDENTIFIED BY "Fixture-Reader_2026"');
    await sql('CREATE USER se7e_denied IDENTIFIED BY "Fixture-Denied_2026"');
    await sql('GRANT SELECT ON DBA.se7e_source_identity TO se7e_reader');
    final expected = await current();
    for (final user in ['reader', 'denied']) {
      final principal = config.copyWith(
        connectionString: config.connectionString.replaceFirst(
          'UID=DBA;PWD=Fixture-SA_2026',
          'UID=se7e_$user;PWD=Fixture-${user == 'reader' ? 'Reader' : 'Denied'}_2026',
        ),
      );
      final result = await probe.inspect(principal, runId);
      if (user == 'denied') {
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<domain.DatabaseFailure>());
        expect((result.exceptionOrNull()! as domain.Failure).code, 'SOURCE_IDENTITY_UNAVAILABLE');
        continue;
      }
      expect(result.getOrThrow().identityHash, expected.identityHash);
      final reader = (await service.connect(principal.connectionString)).getOrThrow().id;
      try {
        for (final statement in [
          'UPDATE DBA.se7e_source_identity SET version=1 WHERE singleton=1',
          'DELETE FROM DBA.se7e_source_identity WHERE singleton=1',
          "INSERT INTO DBA.se7e_source_identity VALUES(1,1,'11111111-1111-4111-8111-111111111111')",
          'DROP TABLE DBA.se7e_source_identity',
          'ALTER TABLE DBA.se7e_source_identity ADD unsafe INTEGER',
        ]) {
          expect((await service.executeQuery(statement, connectionId: reader)).isError(), isTrue);
        }
      } finally {
        (await service.disconnect(reader)).getOrThrow();
      }
    }
    expect((await current()).identityHash, expected.identityHash);
  });
  test('stale source cannot open DML transaction on replacement identity', () async {
    final factory = OdbcSqlOperationTransactionFactory(service, _Strings(), limiter);
    final result = await factory.open(
      SqlOperationTarget(
        config: config,
        database: runId,
        scopeHash: 'a' * 64,
        authorizationHash: 'fixture',
        expectedSource: ExpectedSource(dialect: 'sybase', identityHash: '0' * 64),
      ),
      const Duration(seconds: 15),
    );
    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull().toString(), contains('Executing connection does not match'));
  });
  test('verified transactional INSERT commits with the same enrolled source', () async {
    await sql(
      'CREATE TABLE operation_fixture (id INTEGER DEFAULT AUTOINCREMENT PRIMARY KEY, marker VARCHAR(30) UNIQUE NOT NULL)',
    );
    final factory = OdbcSqlOperationTransactionFactory(service, _Strings(), limiter);
    final target = SqlOperationTarget(
      config: config,
      database: runId,
      scopeHash: 'a' * 64,
      authorizationHash: 'fixture',
      expectedSource: await current(),
    );
    final tx = (await factory.open(target, const Duration(seconds: 15))).getOrThrow();
    try {
      const step = SqlOperationStep(
        id: 'insert',
        effect: SqlOperationEffect.insert,
        sql: 'INSERT INTO operation_fixture(marker) VALUES(:marker)',
        params: {},
        outputs: {},
        affectedRows: SqlRowBounds(1, 1),
      );
      final result = (await tx.execute(step, {
        'marker': const SqlScalar(SqlScalarType.string, 'fixture'),
      }, const Duration(seconds: 15))).getOrThrow();
      expect(result.directlyAffectedRows, 1);
      (await tx.commit(const Duration(seconds: 15))).getOrThrow();
    } finally {
      (await tx.close()).getOrThrow();
    }
    expect((await sql('SELECT COUNT(*) FROM operation_fixture')).rows.single.single, 1);
    final rollback = (await factory.open(target, const Duration(seconds: 15))).getOrThrow();
    try {
      const step = SqlOperationStep(
        id: 'rollback',
        effect: SqlOperationEffect.insert,
        sql: 'INSERT INTO operation_fixture(marker) VALUES(:marker)',
        params: {},
        outputs: {},
        affectedRows: SqlRowBounds(1, 1),
      );
      (await rollback.execute(step, {
        'marker': const SqlScalar(SqlScalarType.string, 'rolled-back'),
      }, const Duration(seconds: 15))).getOrThrow();
      (await rollback.rollback(const Duration(seconds: 15))).getOrThrow();
    } finally {
      (await rollback.close()).getOrThrow();
    }
    expect((await sql('SELECT COUNT(*) FROM operation_fixture')).rows.single.single, 1);
  });
}

class _Strings implements IConfigConnectionStringSource {
  @override
  String generateConnectionString(Config config) => config.connectionString;
  @override
  String generateConnectionStringForPersistence(Config config) => config.connectionString;
  @override
  String resolveConnectionString(Config config) => config.connectionString;
}
