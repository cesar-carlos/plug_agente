import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/expected_structure.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_verified_query.dart';
import 'package:plug_agente/infrastructure/external_services/source_schema_sql.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_sql_params_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

import '../../application/services/sql_operation_executor_test.dart' show fixtureConfig;
import 'odbc_sql_operation_transaction_test.dart' show Native, Strings, info;

void main() {
  setUpAll(() => registerFallbackValue(const odbc.ConnectionOptions()));
  late Native native;
  late Strings strings;
  late DirectOdbcConnectionLimiter limiter;
  late OdbcSourceDiscovery sessions;
  late OdbcVerifiedQuery query;
  final metadataSql = OdbcSourceDiscovery.metadataSql('postgres');
  const metadata = odbc.QueryResult(
    columns: ['db', 'cluster_id', 'db_id'],
    rows: [
      ['test_db', 'cluster', '17'],
    ],
    rowCount: 1,
  );
  setUp(() {
    native = Native();
    strings = Strings();
    limiter = DirectOdbcConnectionLimiter(maxConcurrent: 1, acquireTimeout: const Duration(seconds: 1));
    sessions = OdbcSourceDiscovery(native, strings, limiter);
    query = OdbcVerifiedQuery(sessions);
    when(() => strings.resolveConnectionString(fixtureConfig)).thenReturn('DRIVER={fixture};DATABASE=test_db;');
    when(() => native.connect(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Success(
        odbc.Connection(id: 'dedicated', connectionString: '', createdAt: DateTime.utc(2026), isActive: true),
      ),
    );
    when(() => native.disconnect('dedicated')).thenAnswer((_) async => const Success(unit));
    when(() => native.getConnectionDbmsInfo('dedicated')).thenAnswer((_) async => Success(info('postgres')));
    when(
      () => native.executeQueryNamed('dedicated', metadataSql, const {}),
    ).thenAnswer((_) async => const Success(metadata));
    when(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['id'],
          rows: [
            [7],
          ],
          rowCount: 1,
        ),
      ),
    );
  });
  Future<ExpectedSource> expected() async {
    final proof = await OdbcSourceDiscovery.inspectConnection(native, 'dedicated', fixtureConfig, 'test_db');
    clearInteractions(native);
    return ExpectedSource(dialect: 'postgres', identityHash: proof.identityHash);
  }

  QueryRequest request(ExpectedSource identity) => QueryRequest(
    id: 'read',
    agentId: 'agent',
    query: 'SELECT id FROM fixture',
    timestamp: DateTime.utc(2026),
    sqlHandlingMode: SqlHandlingMode.preserve,
    expectedSource: identity,
  );
  const structure = ExpectedStructure([
    ExpectedResource(SchemaResource(schema: 'public', name: 'fixture', type: 'table'), [
      {'name': 'id', 'nativeType': 'int4', 'nullable': false, 'size': 10, 'scale': 0},
    ]),
  ]);
  const tables = odbc.QueryResult(
    columns: ['TABLE_SCHEM', 'TABLE_NAME', 'TABLE_TYPE'],
    rows: [
      ['public', 'fixture', 'TABLE'],
    ],
    rowCount: 1,
  );
  const columns = odbc.QueryResult(
    columns: ['TABLE_SCHEM', 'TABLE_NAME', 'COLUMN_NAME', 'TYPE_NAME', 'NULLABLE', 'COLUMN_SIZE', 'DECIMAL_DIGITS'],
    rows: [
      ['public', 'fixture', 'id', 'int4', 0, 10, 0],
    ],
    rowCount: 1,
  );
  void catalog() {
    when(
      () => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'tables'), any()),
    ).thenAnswer((_) async => const Success(tables));
    when(
      () => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any()),
    ).thenAnswer((_) async => const Success(columns));
  }

  QueryRequest structural(ExpectedSource identity) => QueryRequest(
    id: 'read',
    agentId: 'agent',
    query: 'SELECT id FROM fixture',
    timestamp: DateTime.utc(2026),
    sqlHandlingMode: SqlHandlingMode.preserve,
    expectedSource: identity,
    expectedStructure: structure,
  );
  test('structural proof before and after SELECT uses the same native connection', () async {
    final identity = await expected();
    catalog();
    final result = await query.execute(structural(identity), fixtureConfig, 'test_db', const Duration(seconds: 3));
    expect(result.isSuccess(), isTrue);
    verify(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any())).called(2);
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
    verify(() => native.connect(any(), options: any(named: 'options'))).called(1);
  });
  test('used-column drift before SELECT refuses dispatch without reconnect', () async {
    final identity = await expected();
    catalog();
    when(
      () => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any()),
    ).thenAnswer((_) async => const Success(odbc.QueryResult(columns: [], rows: [], rowCount: 0)));
    final result = await query.execute(structural(identity), fixtureConfig, 'test_db', const Duration(seconds: 3));
    expect((result.exceptionOrNull()! as domain.Failure).code, 'SOURCE_STRUCTURE_MISMATCH');
    verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
    await Future<void>.delayed(Duration.zero);
    verify(() => native.disconnect('dedicated')).called(1);
  });
  test('used-column drift after SELECT discards the materialized rows', () async {
    final identity = await expected();
    catalog();
    var calls = 0;
    when(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any())).thenAnswer(
      (_) async =>
          ++calls == 1 ? const Success(columns) : const Success(odbc.QueryResult(columns: [], rows: [], rowCount: 0)),
    );
    final result = await query.execute(structural(identity), fixtureConfig, 'test_db', const Duration(seconds: 3));
    expect((result.exceptionOrNull()! as domain.Failure).code, 'SOURCE_STRUCTURE_MISMATCH');
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
    verify(() => native.connect(any(), options: any(named: 'options'))).called(1);
  });
  test('procedural and bundled schema gates accept exactly the new structural contract', () async {
    final params = <String, dynamic>{
      'sql': 'SELECT id FROM public.fixture WHERE id=:id',
      'params': {'id': 1},
      'client_token': 'fixture-token',
      'database': 'test_db',
      'expectedSource': {'version': 1, 'dialect': 'postgres', 'identityHash': 'a' * 64},
      'expectedStructure': {
        'version': 1,
        'resources': [
          {
            'resource': {'schema': 'public', 'name': 'fixture', 'type': 'table'},
            'columns': [
              {'name': 'id', 'nativeType': 'int4', 'nullable': false, 'size': 10, 'scale': 0},
            ],
          },
        ],
      },
      'options': {'execution_mode': 'preserve', 'max_rows': 100, 'timeout_ms': 30000},
    };
    const gate = RpcRequestSchemaSqlParamsValidator();
    expect(gate.validateSqlExecuteParams(params, 5000).isSuccess(), isTrue);
    final loader = TransportSchemaLoader();
    await loader.loadAll();
    expect(loader.get(TransportSchemaIds.paramsSqlExecute)!.validate(params).isValid, isTrue);
    expect(
      gate.validateSqlExecuteParams({
        ...params,
        'expectedStructure': {'sql': 'SELECT secret'},
      }, 5000).isError(),
      isTrue,
    );
    final unbound = Map<String, dynamic>.from(params)..remove('expectedSource');
    expect(gate.validateSqlExecuteParams(unbound, 5000).isError(), isTrue);
  });
  test('late structural metadata cannot launch the next command after the budget', () async {
    final identity = await expected();
    catalog();
    fakeAsync((async) {
      final pending = Completer<Result<odbc.QueryResult>>();
      when(
        () => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'tables'), any()),
      ).thenAnswer((_) => pending.future);
      domain.Failure? failure;
      query.execute(structural(identity), fixtureConfig, 'test_db', const Duration(seconds: 30)).then((result) {
        expect(result.isError(), isTrue);
        failure = result.exceptionOrNull()! as domain.Failure;
      });
      async.flushMicrotasks();
      verify(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'tables'), any())).called(1);
      // Advance timers without advancing the real stopwatch, reproducing an early timeout.
      async.elapse(const Duration(seconds: 30));
      expect(failure, isA<domain.DatabaseFailure>());
      expect(failure!.cause, isA<TimeoutException>());
      expect(limiter.activeCount, 1);
      verifyNever(() => native.disconnect('dedicated'));
      pending.complete(const Success(tables));
      async.flushMicrotasks();
      verifyNever(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any()));
      verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
      verify(() => native.disconnect('dedicated')).called(1);
      expect(limiter.activeCount, 0);
    });
  });
  for (final afterRead in [false, true]) {
    test('constraint drift ${afterRead ? 'after' : 'before'} SELECT refuses result without replay', () async {
      final identity = await expected();
      catalog();
      final enforced = ExpectedStructure([
        ExpectedResource(structure.resources.single.resource, structure.resources.single.columns, {
          'primaryKeys': [
            {
              'name': 'pk_fixture',
              'columns': ['id'],
              'status': 'enabled',
            },
          ],
          'uniqueKeys': <Object?>[],
          'foreignKeys': <Object?>[],
        }),
      ]);
      var checks = 0;
      when(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'primary'), any())).thenAnswer(
        (_) async => Success(
          odbc.QueryResult(
            columns: ['PK_NAME', 'COLUMN_NAME', 'KEY_SEQ', 'CONSTRAINT_STATUS'],
            rows: [
              ['pk_fixture', 'id', 1, if (afterRead && ++checks == 1) 'enabled' else 'disabled'],
            ],
            rowCount: 1,
          ),
        ),
      );
      final result = await query.execute(
        QueryRequest(
          id: 'constraint',
          agentId: 'agent',
          query: 'SELECT id FROM fixture',
          timestamp: DateTime.utc(2026),
          sqlHandlingMode: SqlHandlingMode.preserve,
          expectedSource: identity,
          expectedStructure: enforced,
        ),
        fixtureConfig,
        'test_db',
        const Duration(seconds: 2),
      );
      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as domain.Failure).code, 'SOURCE_STRUCTURE_MISMATCH');
      if (afterRead) {
        verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
      } else {
        verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
      }
    });
  }
  test('metadata nullable fields survive wire sanitization', () {
    final response =
        RpcWireMap.sanitizeRpcResponseWirePayload({
              'jsonrpc': '2.0',
              'id': 'schema',
              'result': {
                'contractVersion': 1,
                'identity': <String, Object?>{},
                'resources': [
                  {
                    'resource': {'schema': null},
                    'columns': [
                      {'nullable': null, 'size': null, 'scale': null},
                    ],
                  },
                ],
                'metadataPage': {'nextOffset': null},
              },
            })
            as Map<String, dynamic>;
    final result = response['result'] as Map<String, dynamic>;
    expect((result['metadataPage'] as Map<String, dynamic>).containsKey('nextOffset'), isTrue);
    final first = (result['resources'] as List<dynamic>).first as Map<String, dynamic>;
    expect((first['resource'] as Map<String, dynamic>).containsKey('schema'), isTrue);
  });
  test('both native checks and read use the same connection without reconnect', () async {
    final identity = await expected();
    final result = (await query.execute(
      request(identity),
      fixtureConfig,
      'test_db',
      const Duration(seconds: 1),
    )).getOrThrow();
    expect(result.data, [
      {'id': 7},
    ]);
    verify(() => native.executeQueryNamed('dedicated', metadataSql, const {})).called(2);
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
    final options =
        verify(() => native.connect(any(), options: captureAny(named: 'options'))).captured.single
            as odbc.ConnectionOptions;
    expect(options.autoReconnectOnConnectionLost, isFalse);
    expect(options.replayQueriesAfterReconnect, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(limiter.activeCount, 0);
  });
  test('business SQL errors retain SQL classification instead of identity failure', () async {
    final identity = await expected();
    when(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).thenAnswer(
      (_) async => const Failure(odbc.QueryError(message: 'Syntax error', sqlState: '42000', nativeCode: 156)),
    );
    final result = await query.execute(request(identity), fixtureConfig, 'test_db', const Duration(seconds: 1));
    final failure = result.exceptionOrNull()! as domain.Failure;
    expect(failure, isA<domain.ValidationFailure>());
    expect(failure.context['odbc_sql_state'], '42000');
    expect(failure.context['reason'], 'sql_validation_failed');
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
    verify(() => native.executeQueryNamed('dedicated', metadataSql, const {})).called(1);
  });
  test('change after SELECT discards rows; no second business read', () async {
    final identity = await expected();
    var calls = 0;
    when(() => native.executeQueryNamed('dedicated', metadataSql, const {})).thenAnswer(
      (_) async => Success(
        ++calls == 1
            ? metadata
            : const odbc.QueryResult(
                columns: ['db', 'cluster_id', 'db_id'],
                rows: [
                  ['test_db', 'cluster', '18'],
                ],
                rowCount: 1,
              ),
      ),
    );
    final result = await query.execute(request(identity), fixtureConfig, 'test_db', const Duration(seconds: 1));
    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull().toString(), contains('Executing connection does not match'));
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
  });
  test('late metadata cannot dispatch business SQL or release admission while native work is pending', () async {
    final identity = await expected();
    final pending = Completer<Result<odbc.QueryResult>>();
    when(() => native.executeQueryNamed('dedicated', metadataSql, const {})).thenAnswer((_) => pending.future);
    final result = await query.execute(request(identity), fixtureConfig, 'test_db', const Duration(milliseconds: 30));
    expect(result.isError(), isTrue);
    expect(limiter.activeCount, 1);
    verifyNever(() => native.disconnect('dedicated'));
    verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
    pending.complete(const Success(metadata));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
    verify(() => native.disconnect('dedicated')).called(1);
    expect(limiter.activeCount, 0);
  });
}
