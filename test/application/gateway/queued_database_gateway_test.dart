import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart' as res;

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _FakeQueryRequest extends Fake implements QueryRequest {}

class _FakeSqlCommand extends Fake implements SqlCommand {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeQueryRequest());
    registerFallbackValue(_FakeSqlCommand());
    registerFallbackValue(const SqlExecutionOptions());
    registerFallbackValue(CancellationToken());
  });

  group('QueuedDatabaseGateway', () {
    test('should route executeQuery through queue', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      final request = QueryRequest(
        id: 'test-id',
        agentId: 'agent-1',
        query: 'SELECT 1',
        timestamp: DateTime.now(),
      );
      final mockResponse = QueryResponse(
        id: 'response-1',
        requestId: 'test-id',
        agentId: 'agent-1',
        data: [
          {'col': 1},
        ],
        timestamp: DateTime.now(),
      );

      when(
        () => delegate.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).thenAnswer((_) async => res.Success(mockResponse));

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals(mockResponse));
      verify(
        () => delegate.executeQuery(
          request,
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).called(1);
    });

    test('should route executeBatch through queue', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      final commands = [
        const SqlCommand(sql: 'INSERT INTO test VALUES (1)'),
      ];
      final mockResults = [
        const SqlCommandResult(index: 0, ok: true, affectedRows: 1),
      ];

      when(
        () => delegate.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).thenAnswer((_) async => res.Success(mockResults));

      final result = await gateway.executeBatch('agent-1', commands);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals(mockResults));
      verify(
        () => delegate.executeBatch(
          'agent-1',
          commands,
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).called(1);
    });

    test('should bypass queue for testConnection', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      when(() => delegate.testConnection(any())).thenAnswer((_) async => const res.Success(true));

      final result = await gateway.testConnection('DSN=test');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), isTrue);
      verify(() => delegate.testConnection('DSN=test')).called(1);
    });

    test('should expose queue metrics and limits', () {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        defaultEnqueueTimeout: const Duration(seconds: 6),
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      expect(gateway.queueSize, equals(0));
      expect(gateway.activeWorkers, equals(0));
      expect(gateway.maxQueueSize, equals(10));
      expect(gateway.maxWorkers, equals(2));
      expect(gateway.enqueueTimeout, equals(const Duration(seconds: 6)));
    });

    test('should reject when queue is full', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 1,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      when(
        () => delegate.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return res.Success(
          QueryResponse(
            id: 'response-1',
            requestId: 'test-id',
            agentId: 'agent-1',
            data: [],
            timestamp: DateTime.now(),
          ),
        );
      });

      // Fill worker and queue
      unawaited(
        gateway.executeQuery(
          QueryRequest(
            id: 'req-1',
            agentId: 'agent-1',
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          ),
        ),
      );
      unawaited(
        gateway.executeQuery(
          QueryRequest(
            id: 'req-2',
            agentId: 'agent-1',
            query: 'SELECT 2',
            timestamp: DateTime.now(),
          ),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // This should be rejected
      final result = await gateway.executeQuery(
        QueryRequest(
          id: 'req-3',
          agentId: 'agent-1',
          query: 'SELECT 3',
          timestamp: DateTime.now(),
        ),
      );

      expect(result.isError(), isTrue);
      final error = result.exceptionOrNull();
      expect(error, isA<ConfigurationFailure>());
      if (error is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(error.context['reason'], equals('sql_queue_full'));
    });

    test('should preserve queue disposal failure for executeBatch', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );
      queue.dispose();

      final result = await gateway.executeBatch(
        'agent-1',
        [const SqlCommand(sql: 'SELECT 1')],
      );

      expect(result.isError(), isTrue);
      final error = result.exceptionOrNull();
      expect(error, isA<ConfigurationFailure>());
      if (error is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(error.context['reason'], equals(SqlPipelineContextConstants.queueDisposedReason));
    });

    test('should include source RPC request id in batch queue failures', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 1,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      when(
        () => delegate.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return const res.Success(<SqlCommandResult>[]);
      });

      unawaited(
        gateway.executeBatch(
          'agent-1',
          [const SqlCommand(sql: 'SELECT 1')],
          sourceRpcRequestId: 'batch-1',
        ),
      );
      unawaited(
        gateway.executeBatch(
          'agent-1',
          [const SqlCommand(sql: 'SELECT 2')],
          sourceRpcRequestId: 'batch-2',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final result = await gateway.executeBatch(
        'agent-1',
        [const SqlCommand(sql: 'SELECT 3')],
        sourceRpcRequestId: 'batch-3',
      );

      expect(result.isError(), isTrue);
      final error = result.exceptionOrNull();
      expect(error, isA<ConfigurationFailure>());
      if (error is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(error.context['reason'], equals('sql_queue_full'));
      expect(error.context['request_id'], equals('batch-3'));
    });

    test('should preserve queue disposal failure for executeNonQuery', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );
      queue.dispose();

      final result = await gateway.executeNonQuery('UPDATE test SET value = 1', null);

      expect(result.isError(), isTrue);
      final error = result.exceptionOrNull();
      expect(error, isA<ConfigurationFailure>());
      if (error is! ConfigurationFailure) {
        fail('expected ConfigurationFailure');
      }
      expect(error.context['reason'], equals(SqlPipelineContextConstants.queueDisposedReason));
    });

    test(
      'should signal cooperative cancel when materialized enqueue times out',
      () async {
        final delegate = _MockDatabaseGateway();
        final queue = SqlExecutionQueue(
          maxQueueSize: 4,
          maxConcurrentWorkers: 1,
          defaultEnqueueTimeout: const Duration(milliseconds: 30),
        );
        final gateway = QueuedDatabaseGateway(
          delegate: delegate,
          queue: queue,
        );
        final firstBlocker = Completer<void>();
        final cooperativeToken = CancellationToken();

        var queryInvocation = 0;
        when(
          () => delegate.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
            database: any(named: 'database'),
            cancellationToken: any(named: 'cancellationToken'),
          ),
        ).thenAnswer((invocation) async {
          queryInvocation++;
          final token = invocation.namedArguments[#cancellationToken] as CancellationToken?;
          if (queryInvocation == 1) {
            await firstBlocker.future;
            return res.Success(
              QueryResponse(
                id: 'response-1',
                requestId: 'blocker',
                agentId: 'agent-1',
                data: [],
                timestamp: DateTime.now(),
              ),
            );
          }
          await Future<void>.delayed(const Duration(seconds: 1));
          if (token?.isCancelled ?? false) {
            return res.Failure(
              QueryExecutionFailure.withContext(
                message: 'SQL execution cancelled',
                context: const {'cooperative_cancel': true},
              ),
            );
          }
          return res.Success(
            QueryResponse(
              id: 'response-2',
              requestId: 'timeout',
              agentId: 'agent-1',
              data: [],
              timestamp: DateTime.now(),
            ),
          );
        });

        unawaited(
          gateway.executeQuery(
            QueryRequest(
              id: 'blocker',
              agentId: 'agent-1',
              query: 'SELECT 1',
              timestamp: DateTime.now(),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final result = await gateway.executeQuery(
          QueryRequest(
            id: 'timeout',
            agentId: 'agent-1',
            query: 'SELECT 2',
            timestamp: DateTime.now(),
          ),
          cancellationToken: cooperativeToken,
        );

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<QueryExecutionFailure>());
        expect(cooperativeToken.isCancelled, isTrue);

        firstBlocker.complete();
      },
    );
    test('should signal cooperative cancel for batch when enqueue times out', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
        defaultEnqueueTimeout: const Duration(milliseconds: 30),
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );
      final firstBlocker = Completer<void>();

      when(
        () => delegate.executeBatch(
          any(),
          any(),
          database: any(named: 'database'),
          options: any(named: 'options'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
          cancellationToken: any(named: 'cancellationToken'),
        ),
      ).thenAnswer((_) async {
        await firstBlocker.future;
        return const res.Success(<SqlCommandResult>[]);
      });

      unawaited(
        gateway.executeBatch(
          'agent-1',
          [const SqlCommand(sql: 'SELECT 1')],
          sourceRpcRequestId: 'batch-blocker',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await gateway.executeBatch(
        'agent-1',
        [const SqlCommand(sql: 'SELECT 2')],
        sourceRpcRequestId: 'batch-timeout',
      );

      expect(result.isError(), isTrue);
      firstBlocker.complete();
    });
    test('propagates cancellation token to delegate for executeNonQuery', () async {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );
      final token = CancellationToken();

      when(
        () => delegate.executeNonQuery(
          any(),
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
          cancellationToken: any(named: 'cancellationToken'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
        ),
      ).thenAnswer((_) async => const res.Success(1));

      final result = await gateway.executeNonQuery(
        'UPDATE t SET v = 1',
        null,
        cancellationToken: token,
        sourceRpcRequestId: 'non-query-1',
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => delegate.executeNonQuery(
          'UPDATE t SET v = 1',
          null,
          cancellationToken: token,
          sourceRpcRequestId: 'non-query-1',
        ),
      ).called(1);
    });
  });
}
