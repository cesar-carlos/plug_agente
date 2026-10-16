import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/application/services/sql_operation_executor.dart';
import 'package:plug_agente/application/services/sql_operation_statement_guard.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_schema.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_verified_query.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/stores/drift_sql_operation_journal.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_database.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

// Deliberately outside test/: run explicitly. Missing engines fail, never skip.
// No .env, registered source, existing DSN, or operational journal is consulted.
void main() {
  final manifestPath = Platform.environment['PERSONA_SQL_FIXTURE_MANIFEST'];
  if (manifestPath == null) throw StateError('PERSONA_SQL_FIXTURE_MANIFEST is required.');
  final manifest = jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;
  final runId = manifest['runId'] as String;
  final root = Directory(manifest['root'] as String).resolveSymbolicLinksSync();
  if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(runId) ||
      !root.endsWith('${Platform.pathSeparator}$runId')) {
    throw StateError('Only explicitly named, isolated fixture databases are accepted.');
  }
  final engines = manifest['engines'] as Map<String, dynamic>;
  late odbc.ServiceLocator locator;
  late odbc.OdbcService service;
  setUpAll(() async {
    locator = odbc.ServiceLocator()..initialize(useAsync: true, asyncWorkerCount: 2);
    service = locator.asyncService;
    (await service.initialize()).getOrThrow();
  });
  tearDownAll(() => locator.shutdown());
  for (final engine in ['postgres', 'mssql', 'sybase']) {
    final fixture = engines[engine] as Map<String, dynamic>?;
    if (fixture == null) throw StateError('Missing mandatory engine: $engine');
    final database = fixture['database'] as String;
    if (engine == 'firebird'
        ? File(database).absolute.path != '$root${Platform.pathSeparator}$runId.fdb'
        : database != runId) {
      throw StateError('Fixture database identity mismatch: $engine');
    }
    group('real ODBC + transaction + journal / $engine', () {
      String? connectionId;
      late SqlOperationJournalDatabase journalDb;
      late File journalFile;
      late DriftSqlOperationJournal journal;
      late SqlOperationExecutor executor;
      late OdbcSqlOperationTransactionFactory transactions;
      late _Authority authority;
      String q(String name) => switch (engine) {
        'postgres' => '"$name"',
        'firebird' => '"${name.toUpperCase()}"',
        _ => '[$name]',
      };
      final projection = '${q('id')} AS "id"';
      final returning = {'postgres', 'firebird'}.contains(engine) ? ' RETURNING $projection' : '';
      Future<odbc.QueryResult> query(String sql) async =>
          (await service.executeQuery(sql, connectionId: connectionId)).getOrThrow();
      Future<int> count() async => (await query('SELECT COUNT(*) FROM operation_fixture')).rows.single.single as int;
      Map<String, dynamic> value(String type, Object v) => {
        'kind': 'value',
        'scalar': {'type': type, 'value': v},
      };
      Map<String, dynamic> step(
        String id,
        String effect,
        String sql, {
        Map<String, dynamic>? params,
        Map<String, dynamic>? outputs,
        int min = 1,
        int max = 1,
      }) => {
        'id': id,
        'effect': effect,
        'sql': sql,
        'params': params ?? {},
        'outputs': outputs ?? {},
        if (effect == 'select') 'expectedRows': {'min': min, 'max': max} else 'affectedRows': {'min': min, 'max': max},
      };
      SqlOperationPlan plan(
        List<Map<String, dynamic>> steps, {
        String? id,
        ExpectedSource? identity,
        Map<String, Object?>? structure,
      }) => const SqlOperationParamsReader().plan({
        'contractVersion': 1,
        'operationId': id ?? const Uuid().v4(),
        'fingerprint': 'b' * 64,
        'sourcePhysicalId': 'c' * 64,
        'database': database,
        'timeoutMs': 30000,
        'maxAffectedRows': 8,
        'steps': steps,
        if (identity != null) 'expectedSource': identity.toJson(),
        'expectedStructure': ?structure,
      });
      Map<String, dynamic> insert(String marker) => step(
        'insert_row',
        'insert',
        'INSERT INTO operation_fixture(marker, amount, revision)${engine == 'mssql' ? ' OUTPUT INSERTED.id AS "id"' : ''} VALUES (:marker, :amount, :revision)$returning',
        params: {
          'marker': value('string', marker),
          'amount': value('decimal', '12.34'),
          'revision': value('integer', '1'),
        },
        outputs: engine == 'sybase' ? {} : {'id': 'integer'},
      );
      Future<SqlOperationJournalEntry> execute(SqlOperationPlan p) async =>
          (await executor.execute(p, 'fixture-only', 'fixture-agent')).getOrThrow();
      setUpAll(() async {
        connectionId = (await service.connect(fixture['connectionString'] as String)).getOrThrow().id;
        final info = (await service.getConnectionDbmsInfo(connectionId!)).getOrThrow();
        final versionSql = switch (engine) {
          'postgres' => 'SHOW server_version',
          'mssql' => "SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(64))",
          'sybase' => "SELECT PROPERTY('ProductVersion')",
          _ => r"SELECT RDB$GET_CONTEXT('SYSTEM', 'ENGINE_VERSION') FROM RDB$DATABASE",
        };
        final version = (await query(versionSql)).rows.single.single;
        stdout.writeln('$engine: engine=$version; ODBC=${info.capabilities.driverVersion}');

        final identity = switch (engine) {
          'mssql' => 'INTEGER IDENTITY(1,1)',
          'sybase' => 'INTEGER DEFAULT AUTOINCREMENT',
          _ => 'INTEGER GENERATED BY DEFAULT AS IDENTITY',
        };
        if (engine == 'firebird') {
          final exists = await query(
            r"SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = 'OPERATION_FIXTURE'",
          );
          if (exists.rows.single.single != 0) await query('DROP TABLE operation_fixture');
        } else {
          await query('DROP TABLE IF EXISTS operation_fixture');
        }
        await query(
          'CREATE TABLE operation_fixture (id $identity PRIMARY KEY, marker VARCHAR(64) NOT NULL UNIQUE, amount DECIMAL(18,2) NOT NULL, revision INTEGER NOT NULL)',
        );
        final config = Config(
          id: runId,
          driverName: engine,
          odbcDriverName: engine,
          connectionString: fixture['connectionString'] as String,
          username: '',
          databaseName: database,
          host: '127.0.0.1',
          port: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        authority = _Authority(config, database);
        transactions = OdbcSqlOperationTransactionFactory(
          service,
          _Strings(),
          DirectOdbcConnectionLimiter(maxConcurrent: 2, acquireTimeout: const Duration(seconds: 5)),
        );
      });
      setUp(() async {
        await query('DELETE FROM operation_fixture');
        journalFile = File('$root${Platform.pathSeparator}$engine-${const Uuid().v4()}.sqlite');
        journalDb = SqlOperationJournalDatabase(NativeDatabase(journalFile));
        authority.denyAt = null;
        authority.expectedSource = null;
        journal = DriftSqlOperationJournal(journalDb);
        executor = SqlOperationExecutor(journal: journal, authorizer: authority, transactions: transactions);
      });
      tearDown(() async => journalDb.close());
      tearDownAll(() async {
        if (connectionId != null) await service.disconnect(connectionId!);
      });
      test('live source discovery confirms actual dialect and identity without business SQL', () async {
        final probe = OdbcSourceDiscovery(
          service,
          _Strings(),
          DirectOdbcConnectionLimiter(maxConcurrent: 2, acquireTimeout: const Duration(seconds: 5)),
        );
        final first = (await probe.inspect(authority.config, database)).getOrThrow();
        final second = (await probe.inspect(authority.config, database)).getOrThrow();
        expect(first.database, database);
        expect(first.dialect, engine);
        expect(first.identityHash, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(first.identityHash, second.identityHash);
        expect(first.identityKind, engine == 'sybase' ? 'provisioned' : 'native');
        expect(first.engineVersion, isNotEmpty);
      });
      Future<ExpectedSource> expected() async {
        final p = await OdbcSourceDiscovery.inspectConnection(service, connectionId!, authority.config, database);
        return ExpectedSource(dialect: p.dialect, identityHash: p.identityHash);
      }

      Future<Result<QueryResponse>> verifiedRead(ExpectedSource identity, String sql) =>
          OdbcVerifiedQuery(
            OdbcSourceDiscovery(
              service,
              _Strings(),
              DirectOdbcConnectionLimiter(maxConcurrent: 2, acquireTimeout: const Duration(seconds: 5)),
            ),
          ).execute(
            QueryRequest(
              id: const Uuid().v4(),
              agentId: 'fixture',
              query: sql,
              timestamp: DateTime.now(),
              sqlHandlingMode: SqlHandlingMode.preserve,
              expectedSource: identity,
            ),
            authority.config,
            database,
            const Duration(seconds: 15),
          );
      Future<Map<String, Object?>> operationStructure(ExpectedSource identity) async {
        final discovery = OdbcSourceDiscovery(
          service,
          _Strings(),
          DirectOdbcConnectionLimiter(maxConcurrent: 2, acquireTimeout: const Duration(seconds: 5)),
        );
        final schema = switch (engine) {
          'postgres' => 'public',
          'mssql' => 'dbo',
          'sybase' => 'DBA',
          _ => null,
        };
        final resource = SchemaResource(
          schema: schema,
          name: engine == 'firebird' ? 'OPERATION_FIXTURE' : 'operation_fixture',
          type: 'table',
        );
        final request = SourceSchemaRequest.fromJson({
          'contractVersion': 1,
          'database': database,
          'client_token': 'fixture-only',
          'expectedSource': identity.toJson(),
          'resources': [resource.toJson()],
          'offset': 0,
          'pageSize': 1,
        });
        final policy = ClientTokenPolicy(
          clientId: 'fixture-client',
          agentId: 'fixture-agent',
          allTables: true,
          allViews: false,
          globalPermissions: ClientPermissionSet.fullAccess,
          rules: const [],
          payload: {'database': database},
        );
        final observed = await OdbcSourceSchema(
          discovery,
        ).readResource(connectionId!, resource, request, policy, () => const Duration(seconds: 10));
        expect(observed['status'], 'available');
        final columns = [
          for (final column in observed['columns']! as List)
            Map<String, Object?>.from(column as Map)..remove('ordinal'),
        ];
        return {
          'version': 1,
          'resources': [
            {'resource': resource.toJson(), 'columns': columns},
          ],
        };
      }

      test('structural operation verifies native metadata on its connection before real INSERT', () async {
        final identity = await expected();
        authority.expectedSource = identity;
        final structure = await operationStructure(identity);
        final receipt = await execute(plan([insert('structure-verified')], identity: identity, structure: structure));
        expect(receipt.state, SqlOperationJournalState.completed);
        expect(receipt.directlyAffectedRows, 1);
        expect(await count(), 1);
      });
      test('structural operation mismatch is terminal before any real DML, including duplicate calls', () async {
        final identity = await expected();
        authority.expectedSource = identity;
        final structure = await operationStructure(identity);
        final resource = (structure['resources']! as List).single as Map;
        final columns = resource['columns']! as List;
        (columns.first as Map)['nativeType'] = '__incompatible__';
        final operation = plan([insert('structure-denied')], identity: identity, structure: structure);
        expect((await execute(operation)).state, SqlOperationJournalState.cancelled);
        expect((await execute(operation)).state, SqlOperationJournalState.cancelled);
        expect(await count(), 0);
      });
      test('verified SELECT uses enrolled durable identity on the executing connection', () async {
        final result = await verifiedRead(await expected(), 'SELECT revision FROM operation_fixture');
        expect(result.isSuccess(), isTrue);
        expect(result.getOrThrow().data, isEmpty);
      });
      test('another native identity rejects before invalid business SQL can run', () async {
        final result = await verifiedRead(
          ExpectedSource(dialect: engine, identityHash: '0' * 64),
          'SELECT nonexistent_column FROM nonexistent_table',
        );
        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull().toString(), contains('Executing connection does not match'));
      });
      test('DML with enrolled durable proof commits on the verified transaction', () async {
        authority.expectedSource = await expected();
        final result = await execute(plan([insert('fenced')]));
        expect(
          result.state,
          SqlOperationJournalState.completed,
        );
        expect(await count(), 1);
      });
      test('DML with different native identity leaves no effect and duplicate does not replay', () async {
        authority.expectedSource = ExpectedSource(dialect: engine, identityHash: '0' * 64);
        final p = plan([insert('wrong-native')]);
        final result = await execute(p);
        expect(result.state, SqlOperationJournalState.cancelled);
        authority.expectedSource = await expected();
        expect((await execute(p)).executionId, result.executionId);
        expect(await count(), 0);
      });
      test('connection identity and transaction capabilities are proven', () async {
        final info = (await service.getConnectionDbmsInfo(connectionId!)).getOrThrow();
        expect(info.dbmsName, isNotEmpty);
        final target = (await authority.authorize(plan([insert('probe')]), 'fixture', 'fixture', [])).getOrThrow();
        final tx = (await transactions.open(target, const Duration(seconds: 10))).getOrThrow();
        (await tx.rollback(const Duration(seconds: 10))).getOrThrow();
        (await tx.close()).getOrThrow();
      });
      test('actual driver identifies the database and typed decimal/string parameters commit', () async {
        final info = (await service.getConnectionDbmsInfo(connectionId!)).getOrThrow();
        expect(info.capabilities.supportsPreparedStatements, isTrue);
        final result = await execute(plan([insert('ação')]));
        expect(result.state, SqlOperationJournalState.completed);
        expect(result.directlyAffectedRows, 1);
        final rows = (await query('SELECT marker, amount, revision FROM operation_fixture')).rows;
        expect(rows.single[0], 'ação');
        expect(rows.single[1].toString(), anyOf('12.34', '12.340000'));
        expect(rows.single[2], 1);
      });
      test('generated identifier binds a later step on the same connection', () async {
        final steps = [insert('generated')];
        if (engine == 'sybase') {
          steps.add(
            step(
              'identity',
              'select',
              'SELECT id FROM operation_fixture WHERE marker=:marker',
              params: {'marker': value('string', 'generated')},
              outputs: {'id': 'integer'},
            ),
          );
        }
        steps.add(
          step(
            'update_row',
            'update',
            'UPDATE operation_fixture SET amount=:amount WHERE id=:id$returning',
            params: {
              'amount': value('decimal', '99.25'),
              'id': {'kind': 'step_output', 'stepId': engine == 'sybase' ? 'identity' : 'insert_row', 'output': 'id'},
            },
          ),
        );
        final result = await execute(plan(steps));
        expect(result.state, SqlOperationJournalState.completed);
        expect(result.directlyAffectedRows, 2);
        expect((await query('SELECT amount FROM operation_fixture')).rows.single.single.toString(), '99.25');
      });
      test('excess affected rows rolls back all previous steps', () async {
        final p = plan([
          insert('one'),
          {...insert('two'), 'id': 'second'},
          step(
            'too_many',
            'update',
            'UPDATE operation_fixture SET revision=:revision WHERE revision=:expected$returning',
            params: {'revision': value('integer', '2'), 'expected': value('integer', '1')},
          ),
        ]);
        expect((await execute(p)).state, SqlOperationJournalState.rolledBack);
        expect(await count(), 0);
      });
      test('concurrency condition matching zero rows rolls back', () async {
        final p = plan([
          insert('one'),
          step(
            'stale',
            'update',
            'UPDATE operation_fixture SET revision=:revision WHERE revision=:expected$returning',
            params: {'revision': value('integer', '2'), 'expected': value('integer', '999')},
          ),
        ]);
        expect((await execute(p)).state, SqlOperationJournalState.rolledBack);
        expect(await count(), 0);
      });
      test('DELETE proves its affected count and commits', () async {
        final p = plan([
          insert('one'),
          step(
            'delete_row',
            'delete',
            'DELETE FROM operation_fixture WHERE marker=:marker$returning',
            params: {'marker': value('string', 'one')},
          ),
        ]);
        final result = await execute(p);
        expect(result.state, SqlOperationJournalState.completed);
        expect(result.directlyAffectedRows, 2);
        expect(await count(), 0);
      });
      test('durable journal suppresses duplicate dispatch', () async {
        final p = plan([insert('one')]);
        final original = await execute(p);
        final duplicate = await execute(p);
        expect(original.state, SqlOperationJournalState.completed);
        expect(duplicate.executionId, original.executionId);
        expect(await count(), 1);
      });
      test('MCP compiled INSERT/UPDATE/DELETE commit with exact direct counts', () async {
        final compiled =
            jsonDecode(File('$root${Platform.pathSeparator}compiled-commands.json').readAsStringSync())
                as Map<String, dynamic>;
        final p = const SqlOperationParamsReader().plan(
          (compiled[engine] as Map<String, dynamic>)['success'] as Map<String, dynamic>,
        );
        p.steps.forEach(const SqlOperationStatementGuard().validate);
        final result = await execute(p);
        expect(result.state, SqlOperationJournalState.completed);
        expect(result.directlyAffectedRows, 3);
        expect(await count(), 0);
      });
      if (engine == 'firebird') {
        final compiled =
            jsonDecode(File('$root${Platform.pathSeparator}compiled-commands.json').readAsStringSync())
                as Map<String, dynamic>;
        for (final read in (compiled[engine] as Map<String, dynamic>)['reads'] as List<dynamic>) {
          final sample = read as Map<String, dynamic>;
          test('MCP Firebird SELECT ${sample['name']} executes its own validated grammar', () async {
            expect((await execute(plan([insert('query')]))).state, SqlOperationJournalState.completed);
            final result = (await service.executeQueryNamed(
              connectionId!,
              sample['sql'] as String,
              Map<String, Object?>.from(sample['params'] as Map),
            )).getOrThrow();
            expect(result.additionalResults, isEmpty);
            expect(result.refCursorResults, isEmpty);
            expect(result.rowCount, result.rows.length);
            expect(
              result.columns.map((v) => v.toLowerCase()).toList(),
              sample['name'] == 'aggregate' ? ['revision', 'amount'] : ['id', 'amount'],
            );
            expect(result.rows.length, sample['name'] == 'empty' ? 0 : 1);
            if (result.rows.isNotEmpty) {
              expect(result.rows.single[0], greaterThan(0));
              expect(result.rows.single[1].toString(), anyOf('12.34', '12.340000'));
            }
          });
        }
      }
      test('MCP compiled concurrency guard rolls back its INSERT', () async {
        final compiled =
            jsonDecode(File('$root${Platform.pathSeparator}compiled-commands.json').readAsStringSync())
                as Map<String, dynamic>;
        final p = const SqlOperationParamsReader().plan(
          (compiled[engine] as Map<String, dynamic>)['stale'] as Map<String, dynamic>,
        );
        p.steps.forEach(const SqlOperationStatementGuard().validate);
        expect((await execute(p)).state, SqlOperationJournalState.rolledBack);
        expect(await count(), 0);
      });
      test('revocation before commit rolls back real writes', () async {
        authority.denyAt = authority.calls + 3;
        expect((await execute(plan([insert('revoked')]))).state, SqlOperationJournalState.rolledBack);
        expect(await count(), 0);
      });
      test('lost acknowledgement after real commit is unknown and never replayed', () async {
        executor = SqlOperationExecutor(
          journal: journal,
          authorizer: authority,
          transactions: _LoseCommit(transactions),
        );
        final p = plan([insert('committed')]);
        final first = await execute(p);
        expect(first.state, SqlOperationJournalState.outcomeUnknown);
        expect(await count(), 1);
        expect((await execute(p)).executionId, first.executionId);
        expect(await count(), 1);
      });
      test('interrupted journal intent remains unknown and never dispatches', () async {
        final p = plan([insert('never')]);
        (await journal.claim(
          SqlOperationJournalEntry(
            operationId: p.operationId,
            scopeHash: 'a' * 64,
            fingerprint: p.fingerprint,
            contentHash: p.contentHash,
            executionId: const Uuid().v4(),
            state: SqlOperationJournalState.executing,
            updatedAt: DateTime.now(),
          ),
        )).getOrThrow();
        await journalDb.close();
        journalDb = SqlOperationJournalDatabase(NativeDatabase(journalFile));
        journal = DriftSqlOperationJournal(journalDb);
        executor = SqlOperationExecutor(journal: journal, authorizer: authority, transactions: transactions);
        expect((await journal.recoverInterrupted()).getOrThrow(), 1);
        expect((await execute(p)).state, SqlOperationJournalState.outcomeUnknown);
        expect(await count(), 0);
      });
    });
  }
}

class _Strings implements IConfigConnectionStringSource {
  @override
  String resolveConnectionString(Config config) => config.connectionString;
  @override
  String generateConnectionString(Config config) => config.connectionString;
  @override
  String generateConnectionStringForPersistence(Config config) => config.connectionString;
}

class _Authority implements ISqlOperationAuthorizer {
  _Authority(this.config, this.database);
  final Config config;
  final String database;
  ExpectedSource? expectedSource;
  int calls = 0;
  int? denyAt;
  @override
  Future<Result<SqlOperationTarget>> authorize(
    SqlOperationReference reference,
    String token,
    String agentId,
    List<SqlOperationStep> steps,
  ) async {
    if (++calls == denyAt) return Failure(SqlOperationFailure(code: 'DENIED', message: 'Fixture revoked.'));
    return Success(
      SqlOperationTarget(
        config: config,
        database: database,
        scopeHash: 'a' * 64,
        authorizationHash: 'fixture-v1',
        expectedSource: expectedSource,
      ),
    );
  }
}

// Only the acknowledgement is injected as lost; the native commit is real.
class _LoseCommit implements ISqlOperationTransactionFactory {
  _LoseCommit(this.delegate);
  final ISqlOperationTransactionFactory delegate;
  @override
  Future<Result<ISqlOperationTransaction>> open(
    SqlOperationTarget target,
    Duration timeout, {
    SqlOperationPlan? plan,
  }) async => (await delegate.open(target, timeout, plan: plan)).map(_LostAcknowledgement.new);
}

class _LostAcknowledgement implements ISqlOperationTransaction {
  _LostAcknowledgement(this.delegate);
  final ISqlOperationTransaction delegate;
  @override
  Result<void> validatePlan(SqlOperationPlan plan) => delegate.validatePlan(plan);
  @override
  Future<Result<SqlOperationStepResult>> execute(
    SqlOperationStep step,
    Map<String, SqlScalar> parameters,
    Duration timeout,
  ) => delegate.execute(step, parameters, timeout);
  @override
  Future<Result<void>> rollback(Duration timeout) => delegate.rollback(timeout);
  @override
  Future<Result<void>> close() => delegate.close();
  @override
  Future<Result<void>> commit(Duration timeout) async {
    (await delegate.commit(timeout)).getOrThrow();
    return Failure(
      SqlOperationFailure(
        code: 'SQL_OPERATION_NATIVE_FAILED',
        message: 'Injected acknowledgement loss.',
        context: {'outcome_unknown': true},
      ),
    );
  }
}
