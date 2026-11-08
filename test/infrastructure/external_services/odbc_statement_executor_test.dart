import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
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
      expect(cache.values, [11]);
      verify(() => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs'))).called(2);
    });

    test('awaits close of the oldest statement before preparing when LRU is full', () async {
      var nextId = 1;
      when(
        () => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs')),
      ).thenAnswer((_) async => Success(nextId++));
      when(() => service.closeStatement(any(), any())).thenAnswer((_) async => const Success(unit));

      final cache = <String, int>{};
      for (var i = 0; i <= OdbcStatementExecutor.maxPreparedStatementsPerConnection; i++) {
        final result = await executor.getOrPrepareStatement(
          connectionId: 'c1',
          preparedExecution: prepared('SELECT $i'),
          preparedStatements: cache,
          statementKey: 'k$i',
        );
        expect(result.isSuccess(), isTrue);
      }

      verify(() => service.closeStatement('c1', 1)).called(1);
      expect(cache.length, OdbcStatementExecutor.maxPreparedStatementsPerConnection);
      expect(cache.containsKey('k0'), isFalse);
      expect(cache.containsKey('k${OdbcStatementExecutor.maxPreparedStatementsPerConnection}'), isTrue);
    });
  });

  group('closePreparedStatements', () {
    test('concurrent cleanup never closes a handle twice', () async {
      final pending = Completer<Result<void>>();
      when(() => service.closeStatement('c1', 1)).thenAnswer((_) => pending.future);
      final first = executor.closePreparedStatements('c1', [1]);
      expect((await executor.closePreparedStatements('c1', [1])).isError(), isTrue);
      pending.complete(const Success(unit));
      expect((await first).isError(), isTrue);
      verify(() => service.closeStatement('c1', 1)).called(1);
    });
    test('old cleanup completion cannot close or quarantine a recovered handle', () async {
      final oldClose = Completer<Result<void>>();
      final newClose = Completer<Result<void>>();
      when(() => service.closeStatement('c1', 1)).thenAnswer((_) => oldClose.future);
      final oldCleanup = executor.closePreparedStatements('c1', [1, 2]);
      executor.invalidateAfterWorkerRecovery();
      when(() => service.closeStatement('c1', 1)).thenAnswer((_) => newClose.future);
      final newCleanup = executor.closePreparedStatements('c1', [1]);
      oldClose.complete(const Success(unit));
      expect((await oldCleanup).isError(), isTrue);
      expect(discarded, isEmpty);
      newClose.complete(const Success(unit));
      expect((await newCleanup).isSuccess(), isTrue);
      verifyNever(() => service.closeStatement('c1', 2));
    });
    test('an exhausted cleanup budget dispatches no native close', () async {
      executor = OdbcStatementExecutor(
        service: service,
        metrics: metrics,
        markConnectionForDiscard: discarded.add,
        statementCleanupTimeout: Duration.zero,
      );
      expect((await executor.closePreparedStatements('c1', [1])).isError(), isTrue);
      verifyNever(() => service.closeStatement(any(), any()));
    });
    for (final lateFailure in [false, true]) {
      test('timeout quarantines cleanup and ignores late completion ($lateFailure)', () async {
        executor = OdbcStatementExecutor(
          service: service,
          metrics: metrics,
          markConnectionForDiscard: discarded.add,
          statementCleanupTimeout: const Duration(milliseconds: 10),
        );
        final pending = Completer<Result<void>>();
        when(() => service.closeStatement('c1', 1)).thenAnswer((_) => pending.future);
        final closing = executor.closePreparedStatements('c1', [1, 2]);
        // Keep the failing pre-fix test bounded too.
        final result = await closing.timeout(const Duration(milliseconds: 200), onTimeout: () => const Success(unit));
        if (lateFailure) {
          pending.completeError(StateError('Late cleanup error'));
        } else {
          pending.complete(const Success(unit));
        }
        await Future<void>.delayed(Duration.zero);
        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull()! as domain.Failure;
        expect(failure.context['outcome_unknown'], isTrue);
        expect(failure.context['timeout'], isTrue);
        expect(failure.context['retryable'], isFalse);
        expect(discarded, contains('c1'));
        expect((await executor.closePreparedStatements('c1', [1, 2])).isError(), isTrue);
        verify(() => service.closeStatement('c1', 1)).called(1);
        verifyNever(() => service.closeStatement('c1', 2));
        expect(
          (await executor.getOrPrepareStatement(
            connectionId: 'c1',
            preparedExecution: prepared('SELECT 1'),
            preparedStatements: {},
            statementKey: 'k',
          )).isError(),
          isTrue,
        );
        expect(
          (await executor.executePreparedStatementWithTimeout(
            connectionId: 'c1',
            preparedExecution: prepared('SELECT 1'),
            statementId: 1,
          )).isError(),
          isTrue,
        );
        verifyNever(() => service.prepare(any(), any(), timeoutMs: any(named: 'timeoutMs')));
        verifyNever(() => service.executePreparedParamValuesFromObjects(any(), any(), any(), any()));
      });
    }
    test('unconfirmed cleanup stops before the next native close', () async {
      when(() => service.closeStatement('c1', 1)).thenAnswer(
        (_) async => Failure(
          domain.QueryExecutionFailure.withContext(message: 'Unknown', context: const {'outcome_unknown': true}),
        ),
      );
      when(() => service.closeStatement('c1', 2)).thenAnswer((_) async => const Success(unit));
      expect((await executor.closePreparedStatements('c1', [1, 2])).isError(), isTrue);
      verifyNever(() => service.closeStatement('c1', 2));
    });
    test('preserves uncertainty when a later statement cleanup fails', () async {
      when(() => service.closeStatement('c1', 1)).thenAnswer((_) async => Failure(Exception('first failure')));
      when(() => service.closeStatement('c1', 2)).thenAnswer(
        (_) async => Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Unconfirmed close',
            context: const {'outcome_unknown': true, 'retryable': false},
          ),
        ),
      );
      final result = await executor.closePreparedStatements('c1', [1, 2]);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(OdbcErrorInspector.outcomeUnknown(failure), isTrue);
      expect(failure.context['retryable'], isFalse);
      expect(failure.context['secondary_errors'], hasLength(2));
    });
    test('closes every statement id after known failures and reports the failure', () async {
      when(() => service.closeStatement('c1', 1)).thenAnswer((_) async => const Success(unit));
      when(() => service.closeStatement('c1', 2)).thenAnswer((_) async => Failure(Exception('boom')));

      final result = await executor.closePreparedStatements('c1', <int>[1, 2]);
      expect(result.isError(), isTrue);

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

    test('cancels and retains native request ownership on unconfirmed timeout', () async {
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
        throwsA(isA<QueryError>().having((error) => error.details.outcomeUnknown, 'outcomeUnknown', true)),
      );

      expect(discarded, contains('c1'));
      verify(() => service.asyncCancel(9)).called(1);
      verifyNever(() => service.asyncFree(9));
    });

    test('recovers the engine diagnostic when async poll hides a finished statement', () async {
      when(() => service.executeAsyncStart('c1', 'UPDATE t SET amt = amt + 2 WHERE id = 1')).thenAnswer(
        (_) async => const Success(7),
      );
      when(() => service.asyncPoll(7)).thenAnswer(
        (_) async => const Failure(
          QueryError(
            message: 'Failed to complete asyncPoll',
            details: OdbcErrorDetails(operation: 'asyncPoll', code: OdbcErrorCode.query),
          ),
        ),
      );
      when(() => service.asyncGetResult(7)).thenAnswer(
        (_) async => const Failure(
          QueryError(
            message: 'Locked',
            sqlState: '40001',
            nativeCode: -210,
            details: OdbcErrorDetails(operation: 'asyncGetResult', code: OdbcErrorCode.query),
          ),
        ),
      );
      when(() => service.asyncFree(7)).thenAnswer((_) async => const Success(unit));

      final result = await executor.runNativeAsyncQueryWithTimeout(
        connectionId: 'c1',
        query: 'UPDATE t SET amt = amt + 2 WHERE id = 1',
        timeout: const Duration(seconds: 5),
      );

      expect(result.isError(), isTrue);
      final error = result.exceptionOrNull()! as QueryError;
      expect(error.message, 'Locked');
      expect(error.nativeCode, -210);
      expect(discarded, isEmpty);
      verify(() => service.asyncFree(7)).called(1);
    });

    test('keeps a generic async poll failure unconfirmed when no diagnostic exists', () async {
      when(() => service.executeAsyncStart('c1', 'UPDATE t SET amt = 1')).thenAnswer((_) async => const Success(8));
      when(() => service.asyncPoll(8)).thenAnswer(
        (_) async => const Failure(
          QueryError(
            message: 'Failed to complete asyncPoll',
            details: OdbcErrorDetails(operation: 'asyncPoll', code: OdbcErrorCode.query),
          ),
        ),
      );
      when(() => service.asyncGetResult(8)).thenAnswer(
        (_) async => const Failure(
          QueryError(
            message: 'Failed to complete asyncGetResult',
            details: OdbcErrorDetails(operation: 'asyncGetResult', code: OdbcErrorCode.query),
          ),
        ),
      );

      final result = await executor.runNativeAsyncQueryWithTimeout(
        connectionId: 'c1',
        query: 'UPDATE t SET amt = 1',
        timeout: const Duration(seconds: 5),
      );

      expect(result.exceptionOrNull().toString(), contains('Failed to complete asyncPoll'));
      expect(discarded, contains('c1'));
      verifyNever(() => service.asyncFree(8));
    });

    test('records a failed native async cancellation', () async {
      when(() => service.asyncCancel(9)).thenAnswer((_) async => Failure(Exception('cancel failed')));

      await executor.abortAsyncRequest(
        connectionId: 'c1',
        requestId: 9,
      );

      expect(discarded, contains('c1'));
      expect(metrics.timeoutCancelFailureCount, 1);
      expect(metrics.timeoutCancelSuccessCount, 0);
    });
  });

  group('executePreparedStatementWithTimeout', () {
    test('returns the result when no timeout is set', () async {
      when(
        () => service.executePreparedParamValues(
          'c1',
          3,
          any(),
          any(),
        ),
      ).thenAnswer(
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
      final options =
          verify(
                () => service.executePreparedParamValues(
                  'c1',
                  3,
                  any(),
                  captureAny(),
                ),
              ).captured.single
              as StatementOptions;
      expect(options.timeout, isNull);
      expect(
        options.initialBufferSize,
        ConnectionConstants.defaultInitialResultBufferBytes,
      );
    });

    test('seeds StatementOptions with timeout and initialBufferSize', () async {
      when(
        () => service.executePreparedParamValues(
          any(),
          any(),
          any(),
          any(),
        ),
      ).thenAnswer(
        (_) async => const Success(
          QueryResult(columns: ['v'], rows: [], rowCount: 0),
        ),
      );

      await executor.executePreparedStatementWithTimeout(
        connectionId: 'c1',
        preparedExecution: prepared('SELECT 1'),
        statementId: 9,
        timeout: const Duration(seconds: 12),
      );

      final options =
          verify(
                () => service.executePreparedParamValues(
                  'c1',
                  9,
                  any(),
                  captureAny(),
                ),
              ).captured.single
              as StatementOptions;
      expect(options.timeout, const Duration(seconds: 12));
      expect(
        options.initialBufferSize,
        ConnectionConstants.defaultInitialResultBufferBytes,
      );
    });

    test('marks discard and cancels the statement on timeout', () async {
      final never = Completer<Result<QueryResult>>();
      addTearDown(() {
        if (!never.isCompleted) {
          never.complete(const Success(QueryResult(columns: [], rows: [], rowCount: 0)));
        }
      });
      when(
        () => service.executePreparedParamValues(any(), any(), any(), any()),
      ).thenAnswer((_) => never.future);
      when(() => service.cancelStatement('c1', 4)).thenAnswer((_) async => const Success(unit));

      await expectLater(
        executor.executePreparedStatementWithTimeout(
          connectionId: 'c1',
          preparedExecution: prepared('SELECT 1'),
          statementId: 4,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<QueryError>().having((error) => error.details.outcomeUnknown, 'outcomeUnknown', true)),
      );

      expect(discarded, contains('c1'));
    });
  });
}
