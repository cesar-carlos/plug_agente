import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_streaming_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

class _MockStreamingGateway extends Mock implements IStreamingDatabaseGateway {}

Future<void> _noopOnChunk(List<Map<String, dynamic>> chunk) async {}

void main() {
  setUpAll(() {
    registerFallbackValue(_noopOnChunk);
  });

  group('QueuedStreamingDatabaseGateway', () {
    test('should route streaming execution through the shared SQL queue', () async {
      final delegate = _MockStreamingGateway();
      final queue = SqlExecutionQueue(
        maxQueueSize: 4,
        maxConcurrentWorkers: 1,
      );
      final gateway = QueuedStreamingDatabaseGateway(
        delegate: delegate,
        queue: queue,
      );

      when(() => delegate.hasActiveStream).thenReturn(false);
      var delegateInvoked = false;
      when(
        () => delegate.executeQueryStream(
          any(),
          any(),
          any(),
          fetchSize: any(named: 'fetchSize'),
          chunkSizeBytes: any(named: 'chunkSizeBytes'),
          executionId: any(named: 'executionId'),
          queryTimeout: any(named: 'queryTimeout'),
          cancellationToken: any(named: 'cancellationToken'),
          cancellationReasonProvider: any(named: 'cancellationReasonProvider'),
        ),
      ).thenAnswer((_) async {
        delegateInvoked = true;
        return const Success(unit);
      });

      final result = await gateway.executeQueryStream(
        'SELECT 1',
        'DSN=test',
        (_) async {},
        executionId: 'stream-1',
      );

      expect(result.isSuccess(), isTrue);
      expect(delegateInvoked, isTrue);
      expect(queue.activeWorkers, 0);
    });
  });
}
