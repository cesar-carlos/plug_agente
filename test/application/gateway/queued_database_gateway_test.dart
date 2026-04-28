import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
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

    test('should expose queue metrics', () {
      final delegate = _MockDatabaseGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      expect(gateway.queueSize, equals(0));
      expect(gateway.activeWorkers, equals(0));
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
    });
  });
}
