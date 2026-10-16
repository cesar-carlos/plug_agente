import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/source_schema_sql.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../application/services/sql_operation_executor_test.dart' show envelope, fixtureConfig;

class Native extends Mock implements odbc.OdbcService {}

class Strings extends Mock implements IConfigConnectionStringSource {}

odbc.DbmsInfo info(String engine, {String? catalog, bool prepared = true}) => odbc.DbmsInfo(
  dbmsName: engine == 'firebird' ? 'Firebird' : engine,
  engineId: engine,
  databaseType: odbc.DatabaseType.unknown,
  maxCatalogNameLen: 255,
  maxSchemaNameLen: 255,
  maxTableNameLen: 255,
  maxColumnNameLen: 255,
  currentCatalog: catalog ?? 'test_db',
  capabilities: odbc.DriverCapabilities(
    supportsPreparedStatements: prepared,
    supportsBatchOperations: false,
    supportsStreaming: false,
    maxRowArraySize: 1,
    driverName: 'test',
    driverVersion: 'test',
    databaseType: odbc.DatabaseType.unknown,
    engineId: engine,
    supportsNativeBcp: false,
  ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const odbc.ConnectionOptions());
    registerFallbackValue(odbc.TransactionAccessMode.readWrite);
    registerFallbackValue(fixtureConfig);
  });
  late Native native;
  late Strings strings;
  late DirectOdbcConnectionLimiter limiter;
  late OdbcSqlOperationTransactionFactory factory;
  final target = SqlOperationTarget(
    config: fixtureConfig,
    database: 'test_db',
    scopeHash: 'a' * 64,
    authorizationHash: 'revision',
  );
  setUp(() {
    native = Native();
    strings = Strings();
    limiter = DirectOdbcConnectionLimiter(maxConcurrent: 1, acquireTimeout: const Duration(seconds: 1));
    factory = OdbcSqlOperationTransactionFactory(native, strings, limiter);
    when(() => strings.resolveConnectionString(any())).thenReturn('DRIVER={test};DATABASE=test_db;');
    when(() => native.connect(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Success(
        odbc.Connection(id: 'dedicated', connectionString: '', createdAt: DateTime.utc(2026), isActive: true),
      ),
    );
    when(() => native.getConnectionDbmsInfo('dedicated')).thenAnswer((_) async => Success(info('postgres')));
    when(() => native.executeQueryNamed('dedicated', any(), const {})).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['operation_database'],
          rows: [
            ['test_db'],
          ],
          rowCount: 1,
        ),
      ),
    );
    when(
      () => native.beginTransaction('dedicated', accessMode: odbc.TransactionAccessMode.readWrite),
    ).thenAnswer((_) async => const Success(7));
    when(() => native.commitTransaction('dedicated', 7)).thenAnswer((_) async => const Success(unit));
    when(() => native.rollbackTransaction('dedicated', 7)).thenAnswer((_) async => const Success(unit));
    when(() => native.disconnect('dedicated')).thenAnswer((_) async => const Success(unit));
  });
  Future<ISqlOperationTransaction> open() async =>
      (await factory.open(target, const Duration(seconds: 1))).getOrThrow();
  final plan = const SqlOperationParamsReader().plan(envelope());
  final first = plan.steps.first;
  SqlOperationStep write(String sql) => SqlOperationStep(
    id: 'w',
    effect: SqlOperationEffect.update,
    sql: sql,
    params: const {},
    outputs: const {},
    affectedRows: const SqlRowBounds(0, 1),
  );
  test('dedicated connection disables replay/reconnect and is used for begin, bindings and commit', () async {
    final session = await open();
    final options =
        verify(() => native.connect(any(), options: captureAny(named: 'options'))).captured.single
            as odbc.ConnectionOptions;
    expect(options.autoReconnectOnConnectionLost, isFalse);
    expect(options.replayQueriesAfterReconnect, isFalse);
    when(() => native.executeQueryNamed('dedicated', first.sql, any())).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['id'],
          rows: [
            [42],
          ],
          rowCount: 1,
        ),
      ),
    );
    final result = (await session.execute(first, {
      'name': const SqlScalar(SqlScalarType.string, 'bound'),
    }, const Duration(seconds: 1))).getOrThrow();
    expect(result.directlyAffectedRows, 1);
    expect(result.rows.single['id'], 42);
    final params =
        verify(() => native.executeQueryNamed('dedicated', first.sql, captureAny())).captured.single
            as Map<String, Object?>;
    expect(params['name'], isA<odbc.ParamValueString>());
    expect((await session.commit(const Duration(seconds: 1))).isSuccess(), isTrue);
    await session.close();
    expect(limiter.activeCount, 0);
    verify(() => native.beginTransaction('dedicated', accessMode: odbc.TransactionAccessMode.readWrite)).called(1);
    verify(() => native.commitTransaction('dedicated', 7)).called(1);
  });
  for (final engine in ['postgres']) {
    test('$engine refuses missing RETURNING before DML and proves count only from complete returned rows', () async {
      when(() => native.getConnectionDbmsInfo('dedicated')).thenAnswer((_) async => Success(info(engine)));
      final session = await open();
      expect(
        (await session.execute(
          write("UPDATE parent SET name = 'returning' WHERE id = 1"),
          const {},
          const Duration(seconds: 1),
        )).isError(),
        isTrue,
      );
      verifyNever(() => native.executeQueryNamed(any(), any(that: startsWith('UPDATE ')), any()));
      when(() => native.executeQueryNamed('dedicated', first.sql, any())).thenAnswer(
        (_) async => const Success(
          odbc.QueryResult(
            columns: ['id'],
            rows: [
              [1],
            ],
            rowCount: 2,
          ),
        ),
      );
      expect((await session.execute(first, const {}, const Duration(seconds: 1))).isError(), isTrue);
      await session.rollback(const Duration(seconds: 1));
      await session.close();
    });
  }
  for (final engine in ['sqlserver', 'sybase_asa']) {
    test('$engine reads direct row count immediately on the same connection, never infers zero', () async {
      when(() => native.getConnectionDbmsInfo('dedicated')).thenAnswer((_) async => Success(info(engine)));
      final session = await open();
      final step = write('UPDATE parent SET name = :name WHERE id = :id');
      final calls = <String>[];
      when(() => native.executeQueryNamed('dedicated', any(), any())).thenAnswer((invocation) async {
        final sql = invocation.positionalArguments[1] as String;
        calls.add(sql);
        return Success(
          sql.startsWith('SELECT @@ROWCOUNT')
              ? const odbc.QueryResult(
                  columns: ['operation_affected_rows'],
                  rows: [
                    ['1'],
                  ],
                  rowCount: 1,
                )
              : const odbc.QueryResult(columns: [], rows: [], rowCount: -1),
        );
      });
      expect((await session.execute(step, const {}, const Duration(seconds: 1))).getOrThrow().directlyAffectedRows, 1);
      expect(calls, [step.sql, 'SELECT @@ROWCOUNT AS operation_affected_rows']);
      when(
        () => native.executeQueryNamed('dedicated', 'SELECT @@ROWCOUNT AS operation_affected_rows', any()),
      ).thenAnswer((_) async => const Success(odbc.QueryResult(columns: [], rows: [], rowCount: 0)));
      expect(
        (await session.execute(step, const {}, const Duration(seconds: 1))).getOrThrow().directlyAffectedRows,
        isNull,
      );
      await session.close();
    });
  }
  test('driver without prepared statements and changed catalog refuse before begin', () async {
    when(
      () => native.getConnectionDbmsInfo('dedicated'),
    ).thenAnswer((_) async => Success(info('postgres', prepared: false)));
    expect((await factory.open(target, const Duration(seconds: 1))).isError(), isTrue);
    when(
      () => native.getConnectionDbmsInfo('dedicated'),
    ).thenAnswer((_) async => Success(info('postgres', catalog: 'other')));
    when(() => native.executeQueryNamed('dedicated', any(), const {})).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['operation_database'],
          rows: [
            ['other'],
          ],
          rowCount: 1,
        ),
      ),
    );
    expect((await factory.open(target, const Duration(seconds: 1))).isError(), isTrue);
    verifyNever(() => native.beginTransaction(any(), accessMode: any(named: 'accessMode')));
  });
  for (final engine in ['postgres', 'sqlserver', 'sybase_asa']) {
    test('$engine proves exact database independently of broken catalog hint', () async {
      when(
        () => native.getConnectionDbmsInfo('dedicated'),
      ).thenAnswer((_) async => Success(info(engine, catalog: 'truncated')));
      final session = await open();
      verify(() => native.executeQueryNamed('dedicated', any(), const {})).called(1);
      await session.rollback(const Duration(seconds: 1));
      await session.close();
    });
  }
  test('missing, incomplete or multiple metadata rows refuse before begin', () async {
    for (final proof in [
      const odbc.QueryResult(columns: ['operation_database'], rows: [], rowCount: 0),
      const odbc.QueryResult(
        columns: ['operation_database'],
        rows: [
          ['test_db'],
        ],
        rowCount: 2,
      ),
      const odbc.QueryResult(
        columns: ['operation_database'],
        rows: [
          ['test_db'],
          ['other'],
        ],
        rowCount: 2,
      ),
      const odbc.QueryResult(
        columns: ['operation_database'],
        rows: [
          [7],
        ],
        rowCount: 1,
      ),
      const odbc.QueryResult(
        columns: ['operation_database'],
        rows: [
          ['TEST_DB'],
        ],
        rowCount: 1,
      ),
    ]) {
      when(() => native.executeQueryNamed('dedicated', any(), const {})).thenAnswer((_) async => Success(proof));
      expect((await factory.open(target, const Duration(seconds: 1))).isError(), isTrue);
    }
    verifyNever(() => native.beginTransaction(any(), accessMode: any(named: 'accessMode')));
  });
  test('identity mismatch retains typed refusal and never begins DML', () async {
    when(() => native.executeQueryNamed('dedicated', any(), const {})).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['db', 'cluster_id', 'db_id'],
          rows: [
            ['test_db', 'cluster', '17'],
          ],
          rowCount: 1,
        ),
      ),
    );
    final rejected = await factory.open(
      SqlOperationTarget(
        config: target.config,
        database: target.database,
        scopeHash: target.scopeHash,
        authorizationHash: target.authorizationHash,
        expectedSource: ExpectedSource(dialect: 'postgres', identityHash: '0' * 64),
      ),
      const Duration(seconds: 1),
    );
    expect(rejected.isError(), isTrue);
    final failure = rejected.exceptionOrNull()! as SqlOperationFailure;
    expect(failure.code, 'SOURCE_IDENTITY_MISMATCH');
    expect(failure.context['outcome_unknown'], isFalse);
    verifyNever(() => native.beginTransaction(any(), accessMode: any(named: 'accessMode')));
  });
  Future<Result<ISqlOperationTransaction>> guarded({bool drift = false, bool overflow = false}) async {
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'source-discovery-v1',
              'postgres',
              fixtureConfig.host.toLowerCase(),
              fixtureConfig.port,
              'test_db',
              'cluster',
              '17',
            ]),
          ),
        )
        .toString();
    when(() => native.executeQueryNamed('dedicated', any(), const {})).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['db', 'cluster_id', 'db_id'],
          rows: [
            ['test_db', 'cluster', '17'],
          ],
          rowCount: 1,
        ),
      ),
    );
    when(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'tables'), any())).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['table_schem', 'table_name', 'table_type'],
          rows: [
            ['public', 'parent', 'table'],
          ],
          rowCount: 1,
        ),
      ),
    );
    when(() => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any())).thenAnswer(
      (_) async => Success(
        odbc.QueryResult(
          columns: [
            'table_schem',
            'table_name',
            'column_name',
            'type_name',
            'nullable',
            'column_size',
            'decimal_digits',
          ],
          rows: [
            if (drift) ['public', 'parent', 'id', 'int8', 0, 32, 0] else ['public', 'parent', 'id', 'int4', 0, 32, 0],
          ],
          rowCount: 1,
        ),
      ),
    );
    final raw = envelope()
      ..['expectedSource'] = {'version': 1, 'dialect': 'postgres', 'identityHash': identity}
      ..['expectedStructure'] = {
        'version': 1,
        'resources': [
          {
            'resource': {'schema': 'public', 'name': 'parent', 'type': 'table'},
            'columns': [
              {'name': 'id', 'nativeType': 'int4', 'nullable': false, 'size': 32, 'scale': 0},
            ],
          },
        ],
      };
    if (overflow) {
      raw['steps'] = [
        for (var i = 0; i < 30; i++) {...(envelope()['steps'] as List).first as Map, 'id': 'step$i'},
      ];
    }
    final plan = const SqlOperationParamsReader().plan(raw);
    return factory.open(
      SqlOperationTarget(
        config: target.config,
        database: target.database,
        scopeHash: target.scopeHash,
        authorizationHash: target.authorizationHash,
        expectedSource: plan.expectedSource,
      ),
      const Duration(seconds: 1),
      plan: plan,
    );
  }

  test('identity and structural proof use the dedicated connection before transaction begin', () async {
    final session = (await guarded()).getOrThrow();
    verifyInOrder([
      () => native.executeQueryNamed('dedicated', any(that: contains('pg_control_system')), const {}),
      () => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'tables'), any()),
      () => native.executeQueryNamed('dedicated', SourceSchemaSql.query('postgres', 'columns'), any()),
      () => native.executeQueryNamed('dedicated', any(that: contains('pg_control_system')), const {}),
      () => native.beginTransaction('dedicated', accessMode: odbc.TransactionAccessMode.readWrite),
    ]);
    await session.rollback(const Duration(seconds: 1));
    await session.close();
  });
  test('structural drift refuses before begin or business SQL and preserves typed reason', () async {
    final result = await guarded(drift: true);
    expect((result.exceptionOrNull()! as SqlOperationFailure).code, 'SOURCE_STRUCTURE_MISMATCH');
    verifyNever(() => native.beginTransaction(any(), accessMode: any(named: 'accessMode')));
    verifyNever(() => native.executeQueryNamed(any(), any(that: startsWith('INSERT')), any()));
  });
  test('structural verification exceeding 32 statements refuses before identity SQL or begin', () async {
    final result = await guarded(overflow: true);
    expect((result.exceptionOrNull()! as SqlOperationFailure).code, 'SQL_OPERATION_STEP_LIMIT');
    verifyNever(() => native.executeQueryNamed(any(), any(), any()));
    verifyNever(() => native.beginTransaction(any(), accessMode: any(named: 'accessMode')));
  });
  test('native count queries consume the 32-statement budget before executing SQL', () async {
    when(() => native.getConnectionDbmsInfo('dedicated')).thenAnswer((_) async => Success(info('sqlserver')));
    final session = await open();
    final raw = envelope();
    raw['steps'] = [
      for (var n = 0; n < 17; n++)
        {
          'id': 'step$n',
          'effect': 'update',
          'sql': 'UPDATE parent SET name = :name WHERE id = :id',
          'params': <String, dynamic>{},
          'outputs': <String, dynamic>{},
          'affectedRows': {'min': 0, 'max': 1},
        },
    ];
    expect(session.validatePlan(const SqlOperationParamsReader().plan(raw)).isError(), isTrue);
    verifyNever(() => native.executeQueryNamed(any(), any(that: startsWith('UPDATE ')), any()));
    await session.close();
  });
  test('timed-out SQL quarantines connection until native call settles; no concurrent rollback/disconnect', () async {
    final pending = Completer<Result<odbc.QueryResult>>();
    when(() => native.executeQueryNamed('dedicated', first.sql, any())).thenAnswer((_) => pending.future);
    final session = await open();
    expect((await session.execute(first, const {}, const Duration(milliseconds: 5))).isError(), isTrue);
    expect((await session.close()).isError(), isTrue);
    verifyNever(() => native.disconnect(any()));
    expect(limiter.activeCount, 1);
    pending.complete(
      const Success(
        odbc.QueryResult(
          columns: ['id'],
          rows: [
            [1],
          ],
          rowCount: 1,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    verify(() => native.disconnect('dedicated')).called(1);
    expect(limiter.activeCount, 0);
    verifyNever(() => native.rollbackTransaction(any(), any()));
  });
}
