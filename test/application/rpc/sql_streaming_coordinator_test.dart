import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';

class _FakeStreamingGateway implements IStreamingDatabaseGateway {
  bool active = false;
  String? lastExecutionId;
  StreamingCancelReason? lastReason;
  int cancelCount = 0;

  @override
  bool get hasActiveStream => active;

  @override
  Future<Result<void>> cancelActiveStream({
    String? executionId,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    cancelCount++;
    lastExecutionId = executionId;
    lastReason = reason;
    active = false;
    return const Success(unit);
  }

  @override
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 100,
    int chunkSizeBytes = 65536,
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  group('SqlStreamingCoordinator', () {
    test('start and finish maintain active stream indexes', () {
      final coordinator = SqlStreamingCoordinator(gateway: _FakeStreamingGateway());

      final execution = coordinator.markStarted(
        streamId: 'stream-1',
        executionId: 'exec-1',
        requestId: 'req-1',
      );

      expect(coordinator.activeCount, 1);
      expect(coordinator.find(executionId: 'exec-1'), execution);
      expect(coordinator.find(requestId: 'req-1'), execution);

      coordinator.markFinished(execution);

      expect(coordinator.activeCount, 0);
      expect(coordinator.find(executionId: 'exec-1'), isNull);
    });

    test('sql.cancel cancels by execution id and request id', () async {
      final gateway = _FakeStreamingGateway()..active = true;
      final coordinator = SqlStreamingCoordinator(gateway: gateway);
      final execution = coordinator.markStarted(
        streamId: 'stream-1',
        executionId: 'exec-1',
        requestId: 'req-1',
      );

      final byExecution = coordinator.find(executionId: 'exec-1');
      expect(byExecution, execution);

      final result = await coordinator.cancel(execution: byExecution!);

      expect(result.isSuccess(), isTrue);
      expect(gateway.lastExecutionId, 'exec-1');
      expect(gateway.lastReason, StreamingCancelReason.user);
      expect(coordinator.activeCount, 0);

      gateway.active = true;
      final second = coordinator.markStarted(
        streamId: 'stream-2',
        executionId: 'exec-2',
        requestId: 'req-2',
      );
      final byRequest = coordinator.find(requestId: 'req-2');
      expect(byRequest, second);
    });

    test('disconnect cancels all active streams and clears state', () async {
      final gateway = _FakeStreamingGateway()..active = true;
      final coordinator = SqlStreamingCoordinator(gateway: gateway);
      final first = coordinator.markStarted(
        streamId: 'stream-1',
        executionId: 'exec-1',
        requestId: 'req-1',
      );
      final second = coordinator.markStarted(
        streamId: 'stream-2',
        executionId: 'exec-2',
        requestId: 'req-2',
      );

      await coordinator.cancelActiveStreamOnDisconnect();

      expect(gateway.cancelCount, 1);
      expect(gateway.lastExecutionId, isNull);
      expect(gateway.lastReason, StreamingCancelReason.socketDisconnect);
      expect(coordinator.activeCount, 0);
      expect(first.cancellationToken.isCancelled, isTrue);
      expect(second.cancellationToken.isCancelled, isTrue);
      expect(first.cancelReason, StreamingCancelReason.socketDisconnect);
      expect(second.cancelReason, StreamingCancelReason.socketDisconnect);
    });

    test('disconnect before gateway registers active stream cancels by token and clears state', () async {
      final gateway = _FakeStreamingGateway();
      final coordinator = SqlStreamingCoordinator(gateway: gateway);
      final execution = coordinator.markStarted(
        streamId: 'stream-1',
        executionId: 'exec-1',
        requestId: 'req-1',
      );

      await coordinator.cancelActiveStreamOnDisconnect();

      expect(gateway.cancelCount, 0);
      expect(execution.cancellationToken.isCancelled, isTrue);
      expect(execution.cancelReason, StreamingCancelReason.socketDisconnect);
      expect(coordinator.activeCount, 0);
    });
  });
}
