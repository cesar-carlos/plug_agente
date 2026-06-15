import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:result_dart/result_dart.dart';

class _MockQueryService extends Mock implements IQueryService {}

void main() {
  setUpAll(() {
    registerFallbackValue(ResultEncoding.rowMajor);
    registerFallbackValue(const <ParamValue>[]);
  });

  late _MockQueryService queries;
  late OdbcResultEncodingExecutor executor;

  setUp(() {
    dotenv.clean();
    queries = _MockQueryService();
    executor = OdbcResultEncodingExecutor(queries);
  });

  const sampleResult = QueryResult(
    columns: ['v'],
    rows: [
      [1],
    ],
    rowCount: 1,
  );

  OdbcPreparedQueryExecution prepared(String sql, [Map<String, dynamic>? params]) =>
      OdbcPreparedQueryExecution(sql: sql, parameters: params);

  group('row-major (default) path', () {
    test('uses executeQuery for parameterless SQL on SQL Anywhere default', () async {
      when(
        () => queries.executeQuery('SELECT 1', connectionId: 'c1'),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute(
        'c1',
        prepared('SELECT 1'),
        databaseType: DatabaseType.sybaseAnywhere,
      );

      expect(result.isSuccess(), isTrue);
      verify(() => queries.executeQuery('SELECT 1', connectionId: 'c1')).called(1);
      verifyNever(
        () => queries.executeQueryParamValues(
          any(),
          any(),
          any(),
          resultEncoding: any(named: 'resultEncoding'),
        ),
      );
    });

    test('uses executeQueryNamed for parameterized SQL on SQL Anywhere', () async {
      when(
        () => queries.executeQueryNamed('c1', 'SELECT :a', {'a': 42}),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute(
        'c1',
        prepared('SELECT :a', {'a': 42}),
        databaseType: DatabaseType.sybaseAnywhere,
      );

      expect(result.isSuccess(), isTrue);
      verify(() => queries.executeQueryNamed('c1', 'SELECT :a', {'a': 42})).called(1);
    });
  });

  group('profile columnar default without env override', () {
    test('uses columnar encoding for SQL Server on highThroughput profile', () async {
      executor = OdbcResultEncodingExecutor(
        queries,
        usageProfile: OdbcUsageProfile.highThroughput,
      );
      when(
        () => queries.executeQueryParamValues(
          'c1',
          'SELECT 1',
          const <ParamValue>[],
          resultEncoding: ResultEncoding.columnar,
        ),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute(
        'c1',
        prepared('SELECT 1'),
        databaseType: DatabaseType.sqlServer,
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => queries.executeQueryParamValues(
          'c1',
          'SELECT 1',
          const <ParamValue>[],
          resultEncoding: ResultEncoding.columnar,
        ),
      ).called(1);
    });
    test('keeps row-major for SQL Server on balancedServer profile', () async {
      when(
        () => queries.executeQuery('SELECT 1', connectionId: 'c1'),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute(
        'c1',
        prepared('SELECT 1'),
        databaseType: DatabaseType.sqlServer,
      );

      expect(result.isSuccess(), isTrue);
      verify(() => queries.executeQuery('SELECT 1', connectionId: 'c1')).called(1);
    });
  });

  group('encoded path (ODBC_RESULT_ENCODING set)', () {
    setUp(() {
      dotenv.loadFromString(envString: 'ODBC_RESULT_ENCODING=columnarCompressed');
    });

    test('uses executeQueryParamValues for parameterless SQL', () async {
      when(
        () => queries.executeQueryParamValues(
          'c1',
          'SELECT 1',
          const <ParamValue>[],
          resultEncoding: ResultEncoding.columnarCompressed,
        ),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute('c1', prepared('SELECT 1'));

      expect(result.isSuccess(), isTrue);
      verify(
        () => queries.executeQueryParamValues(
          'c1',
          'SELECT 1',
          const <ParamValue>[],
          resultEncoding: ResultEncoding.columnarCompressed,
        ),
      ).called(1);
    });

    test('translates named params to positional for parameterized SQL', () async {
      when(
        () => queries.executeQueryParamValues(
          any(),
          any(),
          any(),
          resultEncoding: any(named: 'resultEncoding'),
        ),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute('c1', prepared('SELECT :a', {'a': 42}));

      expect(result.isSuccess(), isTrue);
      final captured = verify(
        () => queries.executeQueryParamValues(
          'c1',
          captureAny(),
          captureAny(),
          resultEncoding: ResultEncoding.columnarCompressed,
        ),
      ).captured;
      final params = captured.last as List<ParamValue>;
      expect(params.any((param) => param is ParamValueInt32 && param.value == 42), isTrue);
    });
  });
}
