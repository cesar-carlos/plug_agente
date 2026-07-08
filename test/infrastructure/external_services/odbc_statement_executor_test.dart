import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_prepared_statement_cache_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const StatementOptions());
  });

  late _MockOdbcService service;
  late MetricsCollector metrics;
  late List<String> discarded;
  late OdbcStatementExecutor executor;

  setUp(() {
    service = _MockOdbcService();
    metrics = MetricsCollector()..clear();
    discarded = <String>[];
    executor = OdbcStatementExecutor(
      service: service,
      metrics: metrics,
      markConnectionForDiscard: discarded.add,
    );
  });

  OdbcPreparedQueryExecution prepared(String sql) => OdbcPreparedQueryExecution(sql: sql, parameters: null);

  group('getOrPrepareStatement', () {
    test('prepares on cache miss and reuses on cache hit', () async {
      when(
        () => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs')),
      ).thenAnswer((_) async => const Success(77));

      final cache = <String, int>{};
      final first = await executor.getOrPrepareStatement(
        connectionId: 'c1',
        preparedExecution: prepared('SELECT 1'),
        preparedStatements: cache,
        statementKey: 'k',
      );
      final second = await executor.getOrPrepareStatement(
        connectionId: 'c1',
        preparedExecution: prepared('SELECT 1'),
        preparedStatements: cache,
        statementKey: 'k',
      );

      expect(first.getOrNull(), 77);
      expect(second.getOrNull(), 77);
      verify(() => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs'))).called(1);
    });

    test('skips Dart LRU cache when native pool policy is active', () async {
      when(
        () => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs')),
      ).thenAnswer((_) async => const Success(11));

      final cache = <String, int>{};
      final first = await executor.getOrPrepareStatement(
        connectionId: 'c1',
        preparedExecution: prepared('SELECT 1'),
        preparedStatements: cache,
        statementKey: 'k',
        cachePolicy: OdbcPreparedStatementCachePolicy.nativePool,
      );
      final second = await executor.getOrPrepareStatement(
        connectionId: 'c1',
        preparedExecution: prepared('SELECT 1'),
        preparedStatements: cache,
        statementKey: 'k',
        cachePolicy: OdbcPreparedStatementCachePolicy.nativePool,
      );

      expect(first.getOrNull(), 11);
      expect(second.getOrNull(), 11);
      expect(cache, isEmpty);
      verify(() => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs'))).called(2);
    });
  });

  group('closePreparedStatements', () {
    test('closes every statement id and swallows individual failures', () async {
      when(() => service.closeStatement('c1', 1)).thenAnswer((_) async => const Success(unit));
      when(() => service.closeStatement('c1', 2)).thenAnswer((_) async => Failure(Exception('boom')));

      await executor.closePreparedStatements('c1', <int>[1, 2]);

      verify(() => service.closeStatement('c1', 1)).called(1);
      verify(() => service.closeStatement('c1', 2)).called(1);
    });
  });

  group('runNativeAsyncQueryWithTimeout', () {
    test('returns the result when the request becomes ready', () async {
      when(() => service.executeAsyncStart('c1', 'SELECT 1')).thenAnswer((_) async => const Success(5));
      when(() => service.asyncPoll(5)).thenAnswer((_) async => const Success(1));
      when(() => service.asyncGetResult(5)).thenAnswer(
        (_) async => const Success(
          QueryResult(
            columns: ['v'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        ),
      );
      when(() => service.asyncFree(5)).thenAnswer((_) async => const Success(unit));

      final result = await executor.runNativeAsyncQueryWithTimeout(
        connectionId: 'c1',
        query: 'SELECT 1',
        timeout: const Duration(seconds: 5),
      );

      expect(result.isSuccess(), isTrue);
      verify(() => service.asyncFree(5)).called(1);
      expect(discarded, isEmpty);
    });

    test('cancels, marks discard and frees on timeout', () async {
      when(() => service.executeAsyncStart('c1', 'SELECT slow')).thenAnswer((_) async => const Success(9));
      when(() => service.asyncPoll(9)).thenAnswer((_) async => const Success(0)); // pending forever
      when(() => service.asyncCancel(9)).thenAnswer((_) async => const Success(unit));
      when(() => service.asyncFree(9)).thenAnswer((_) async => const Success(unit));

      await expectLater(
        executor.runNativeAsyncQueryWithTimeout(
          connectionId: 'c1',
          query: 'SELECT slow',
          // Zero budget forces the deadline check to trip on the first poll
          // without scheduling real delays.
          timeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(discarded, contains('c1'));
      verify(() => service.asyncCancel(9)).called(1);
      verify(() => service.asyncFree(9)).called(1);
    });
  });

  group('executePreparedStatementWithTimeout', () {
    test('returns the result when no timeout is set', () async {
      when(() => service.executePreparedParamValuesFromObjects('c1', 3, const [], null)).thenAnswer(
        (_) async => const Success(
          QueryResult(
            columns: ['v'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        ),
      );

      final result = await executor.executePreparedStatementWithTimeout(
        connectionId: 'c1',
        preparedExecution: prepared('SELECT 1'),
        statementId: 3,
      );

      expect(result.isSuccess(), isTrue);
      expect(discarded, isEmpty);
    });

    test('marks discard and cancels the statement on timeout', () async {
      final never = Completer<Result<QueryResult>>();
      addTearDown(() {
        if (!never.isCompleted) {
          never.complete(const Success(QueryResult(columns: [], rows: [], rowCount: 0)));
        }
      });
      when(
        () => service.executePreparedParamValuesFromObjects(any(), any(), any(), any()),
      ).thenAnswer((_) => never.future);
      when(() => service.cancelStatement('c1', 4)).thenAnswer((_) async => const Success(unit));

      await expectLater(
        executor.executePreparedStatementWithTimeout(
          connectionId: 'c1',
          preparedExecution: prepared('SELECT 1'),
          statementId: 4,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(discarded, contains('c1'));
    });
  });
}
