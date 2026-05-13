import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
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
        ),
      ).thenAnswer((_) async => res.Success(mockResponse));

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals(mockResponse));
      verify(() => delegate.executeQuery(request)).called(1);
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
        ),
      ).thenAnswer((_) async => res.Success(mockResults));

      final result = await gateway.executeBatch('agent-1', commands);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals(mockResults));
      verify(
        () => delegate.executeBatch(
          'agent-1',
          commands,
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
      expect(error.context['reason'], equals('queue_disposed'));
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
      expect(error.context['reason'], equals('queue_disposed'));
    });
  });
}
