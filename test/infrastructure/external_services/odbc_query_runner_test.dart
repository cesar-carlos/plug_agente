import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const StatementOptions());
    registerFallbackValue(<String, dynamic>{});
  });

  late _MockOdbcService service;
  late MetricsCollector metrics;
  late List<String> discarded;
  late OdbcQueryRunner runner;

  setUp(() {
    dotenv.clean();
    service = _MockOdbcService();
    metrics = MetricsCollector()..clear();
    discarded = <String>[];
    final statementExecutor = OdbcStatementExecutor(
      service: service,
      metrics: metrics,
      markConnectionForDiscard: discarded.add,
    );
    runner = OdbcQueryRunner(
      service: service,
      metrics: metrics,
      statementExecutor: statementExecutor,
      resultEncodingExecutor: OdbcResultEncodingExecutor(service),
      markConnectionForDiscard: discarded.add,
    );
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

  QueryRequest request(String sql) => QueryRequest(
    id: 'req',
    agentId: 'agent',
    query: sql,
    timestamp: DateTime(2024, 2, 3),
  );

  group('pure prepared-key helpers', () {
    test('preparedStatementKeyFor is stable regardless of parameter order', () {
      final a = OdbcQueryRunner.preparedStatementKeyFor(prepared('SELECT :a, :b', {'b': 2, 'a': 1}));
      final b = OdbcQueryRunner.preparedStatementKeyFor(prepared('SELECT :a, :b', {'a': 1, 'b': 2}));
      expect(a, b);
    });

    test('collectRepeatedPreparedKeys returns only keys seen more than once', () {
      final repeated = OdbcQueryRunner.collectRepeatedPreparedKeys(const [
        SqlCommand(sql: 'SELECT 1'),
        SqlCommand(sql: 'SELECT 1'),
        SqlCommand(sql: 'SELECT 2'),
      ]);
      expect(repeated.length, 1);
      expect(repeated.single, contains('SELECT 1'));
    });
  });

  group('runWithTimeout', () {
    test('runs a parameterless query through the row-major path without a timeout', () async {
      when(
        () => service.executeQuery('SELECT 1', connectionId: 'c1'),
      ).thenAnswer((_) async => const Success(sampleResult));

      final outcome = await runner.runWithTimeout(
        connId: 'c1',
        request: request('SELECT 1'),
        preparedExecution: prepared('SELECT 1'),
        connectionString: 'DSN=x',
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.response!.data, [
        {'v': 1},
      ]);
    });

    test('marks the connection for discard and rethrows on async timeout', () async {
      when(() => service.executeAsyncStart('c1', 'SELECT slow')).thenAnswer((_) async => const Success(8));
      when(() => service.asyncPoll(8)).thenAnswer((_) async => const Success(0)); // pending
      when(() => service.asyncCancel(8)).thenAnswer((_) async => const Success(unit));
      when(() => service.asyncFree(8)).thenAnswer((_) async => const Success(unit));

      await expectLater(
        runner.runWithTimeout(
          connId: 'c1',
          request: request('SELECT slow'),
          preparedExecution: prepared('SELECT slow'),
          connectionString: 'DSN=x',
          // Zero budget trips the deadline on the first poll without real delays.
          timeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(discarded, contains('c1'));
    });
  });

  group('runPrepared', () {
    test('prepares, executes and closes a named-parameter statement', () async {
      when(
        () => service.prepareNamed('c1', 'SELECT :a', timeoutMs: any(named: 'timeoutMs')),
      ).thenAnswer((_) async => const Success(10));
      when(
        () => service.executePreparedNamed('c1', 10, {'a': 1}, any()),
      ).thenAnswer((_) async => const Success(sampleResult));
      when(() => service.closeStatement('c1', 10)).thenAnswer((_) async => const Success(unit));

      final outcome = await runner.runPrepared(
        connectionId: 'c1',
        request: request('SELECT :a'),
        preparedExecution: prepared('SELECT :a', {'a': 1}),
        timeout: const Duration(seconds: 5),
      );

      expect(outcome.isSuccess, isTrue);
      verify(() => service.closeStatement('c1', 10)).called(1);
    });
  });
}
