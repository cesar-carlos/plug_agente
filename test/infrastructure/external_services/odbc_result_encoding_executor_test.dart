import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(ResultEncoding.rowMajor);
  });

  late _MockOdbcService service;
  late OdbcResultEncodingExecutor executor;

  setUp(() {
    dotenv.clean();
    service = _MockOdbcService();
    executor = OdbcResultEncodingExecutor(service);
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
    test('uses executeQuery for parameterless SQL', () async {
      when(
        () => service.executeQuery('SELECT 1', connectionId: 'c1'),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute('c1', prepared('SELECT 1'));

      expect(result.isSuccess(), isTrue);
      verify(() => service.executeQuery('SELECT 1', connectionId: 'c1')).called(1);
      verifyNever(
        () => service.executeQueryParams(any(), any(), any(), resultEncoding: any(named: 'resultEncoding')),
      );
    });

    test('uses executeQueryNamed for parameterized SQL', () async {
      when(
        () => service.executeQueryNamed('c1', 'SELECT :a', {'a': 1}),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute('c1', prepared('SELECT :a', {'a': 1}));

      expect(result.isSuccess(), isTrue);
      verify(() => service.executeQueryNamed('c1', 'SELECT :a', {'a': 1})).called(1);
    });
  });

  group('encoded path (ODBC_RESULT_ENCODING set)', () {
    setUp(() {
      dotenv.loadFromString(envString: 'ODBC_RESULT_ENCODING=columnarCompressed');
    });

    test('uses executeQueryParams with empty positional params for parameterless SQL', () async {
      when(
        () => service.executeQueryParams(
          'c1',
          'SELECT 1',
          const <Object?>[],
          resultEncoding: ResultEncoding.columnarCompressed,
        ),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute('c1', prepared('SELECT 1'));

      expect(result.isSuccess(), isTrue);
      verify(
        () => service.executeQueryParams(
          'c1',
          'SELECT 1',
          const <Object?>[],
          resultEncoding: ResultEncoding.columnarCompressed,
        ),
      ).called(1);
    });

    test('translates named params to positional for parameterized SQL', () async {
      when(
        () => service.executeQueryParams(any(), any(), any(), resultEncoding: any(named: 'resultEncoding')),
      ).thenAnswer((_) async => const Success(sampleResult));

      final result = await executor.execute('c1', prepared('SELECT :a', {'a': 42}));

      expect(result.isSuccess(), isTrue);
      final captured = verify(
        () => service.executeQueryParams(
          'c1',
          captureAny(),
          captureAny(),
          resultEncoding: ResultEncoding.columnarCompressed,
        ),
      ).captured;
      // The named parameter value is forwarded as a positional argument.
      expect((captured.last as List).contains(42), isTrue);
    });
  });
}
