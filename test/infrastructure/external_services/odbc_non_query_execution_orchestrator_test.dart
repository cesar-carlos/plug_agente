import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_non_query_execution_orchestrator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ConnectionOptions());
    registerFallbackValue(const ConnectionAcquireOptions());
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<Object?>[]);
  });

  group('OdbcNonQueryExecutionOrchestrator', () {
    late MockOdbcService mockService;
    late MockConnectionPool mockConnectionPool;
    late MetricsCollector metrics;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcNonQueryExecutionOrchestrator orchestrator;

    setUp(() {
      mockService = MockOdbcService();
      mockConnectionPool = MockConnectionPool();
      metrics = MetricsCollector()..clear();
      mockSettings = MockOdbcConnectionSettings();

      final connectionManager = OdbcGatewayConnectionManager(
        service: mockService,
        connectionPool: mockConnectionPool,
        directConnectionLimiter: DirectOdbcConnectionLimiter(
          maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
            mockSettings.poolSize,
          ),
          acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
          metricsCollector: metrics,
        ),
        metrics: metrics,
        directConnectionMaxProvider: () => ConnectionConstants.directOdbcConnectionConcurrency(
          mockSettings.poolSize,
        ),
      );
      final statementExecutor = OdbcStatementExecutor(
        service: mockService,
        metrics: metrics,
        markConnectionForDiscard: connectionManager.markConnectionForDiscard,
      );
      orchestrator = OdbcNonQueryExecutionOrchestrator(
        connectionManager: connectionManager,
        service: mockService,
        statementExecutor: statementExecutor,
        optionsResolver: OdbcConnectionOptionsResolver(mockSettings),
        metrics: metrics,
      );

      when(() => mockConnectionPool.discard(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(
        () => mockConnectionPool.getActiveCount(
          connectionString: any(named: 'connectionString'),
        ),
      ).thenAnswer((_) async {
        return const Success(0);
      });
      when(
        () => mockService.prepare(
          any(),
          any(),
          timeoutMs: any(named: 'timeoutMs'),
        ),
      ).thenAnswer((_) async => const Success(9001));
      when(
        () => mockService.executePreparedParamValues(
          any(),
          any(),
          any(),
          any(),
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });
      when(() => mockService.closeStatement(any(), any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockService.cancelStatement(any(), any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockService.asyncCancel(any())).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockService.asyncFree(any())).thenAnswer((_) async {
        return const Success(unit);
      });
    });

    test(
      'should use native async request lifecycle for timed non-query without parameters',
      () async {
        const pooledConnectionId = 'pool-async-non-query-1';
        const asyncRequestId = 41;
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        var pollCount = 0;

        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async => const Success(asyncRequestId));
        when(() => mockService.asyncPoll(asyncRequestId)).thenAnswer((_) async {
          pollCount++;
          return Success(pollCount == 1 ? 0 : 1);
        });
        when(
          () => mockService.asyncGetResult(
            asyncRequestId,
            maxBufferBytes: any(named: 'maxBufferBytes'),
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(columns: [], rows: [], rowCount: 3),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          sql,
          null,
          connectionString,
          timeout: const Duration(milliseconds: 1200),
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 3);
        verify(() => mockService.executeAsyncStart(pooledConnectionId, sql)).called(1);
        verify(() => mockService.asyncPoll(asyncRequestId)).called(2);
        verify(
          () => mockService.asyncGetResult(
            asyncRequestId,
            maxBufferBytes: any(named: 'maxBufferBytes'),
          ),
        ).called(1);
        verify(() => mockService.asyncFree(asyncRequestId)).called(1);
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
        verifyNever(
          () => mockService.executePreparedParamValues(
            any(),
            any(),
            any(),
            any(),
          ),
        );
      },
    );

    test(
      'should fallback to prepared timeout path when async request start is unsupported for non-query',
      () async {
        const pooledConnectionId = 'pool-async-fallback-1';
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';

        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            UnsupportedFeatureError(message: 'async execution unsupported'),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          sql,
          null,
          connectionString,
          timeout: const Duration(milliseconds: 1200),
        );

        expect(result.isSuccess(), isTrue);
        verify(() => mockService.executeAsyncStart(pooledConnectionId, sql)).called(1);
        verify(
          () => mockService.prepare(
            pooledConnectionId,
            sql,
            timeoutMs: any(named: 'timeoutMs'),
          ),
        ).called(1);
        final executePreparedCall = verify(
          () => mockService.executePreparedParamValues(
            pooledConnectionId,
            9001,
            captureAny(),
            captureAny(),
          ),
        );
        executePreparedCall.called(1);
        expect(executePreparedCall.captured[0], isNull);
        expect(executePreparedCall.captured[1], isA<StatementOptions>());
        verify(() => mockService.closeStatement(pooledConnectionId, 9001)).called(1);
      },
    );

    test(
      'should cancel native async non-query request on timeout and discard pooled connection',
      () async {
        const pooledConnectionId = 'pool-async-timeout-1';
        const asyncRequestId = 52;
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';

        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeAsyncStart(
            pooledConnectionId,
            sql,
          ),
        ).thenAnswer((_) async => const Success(asyncRequestId));
        when(() => mockService.asyncPoll(asyncRequestId)).thenAnswer((_) async {
          return const Success(0);
        });
        when(() => mockConnectionPool.discard(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(
          sql,
          null,
          connectionString,
          timeout: const Duration(milliseconds: 20),
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        expect(failure, isA<domain.QueryExecutionFailure>());
        final queryFailure = failure! as domain.QueryExecutionFailure;
        expect(queryFailure.context['timeout'], isTrue);
        expect(queryFailure.context['reason'], 'query_timeout');
        expect(metrics.timeoutCancelSuccessCount, 1);
        verify(() => mockService.asyncCancel(asyncRequestId)).called(1);
        verify(() => mockService.asyncFree(asyncRequestId)).called(1);
        verifyNever(() => mockConnectionPool.release(pooledConnectionId));
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verifyNever(
          () => mockService.prepare(
            any(),
            any(),
            timeoutMs: any(named: 'timeoutMs'),
          ),
        );
      },
    );

    test(
      'should fallback to direct connection on invalid pooled connection id',
      () async {
        const pooledConnectionId = '100000';
        const directConnectionId = 'direct-1';
        const sql = 'UPDATE users SET active = 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';

        when(() => mockConnectionPool.acquire(any(), options: any(named: 'options'))).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            ValidationError(message: 'Invalid connection ID: 100000'),
          );
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: directConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(columns: [], rows: [], rowCount: 5),
          );
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await orchestrator.execute(sql, null, connectionString);

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 5);
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.discard(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );
  });
}
