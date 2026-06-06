import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';

/// Wraps a streaming gateway with the shared [SqlExecutionQueue] so ODBC
/// streaming cannot bypass SQL queue backpressure limits.
class QueuedStreamingDatabaseGateway implements IStreamingDatabaseGateway, IStreamingGatewayDiagnostics {
  QueuedStreamingDatabaseGateway({
    required IStreamingDatabaseGateway delegate,
    required SqlExecutionQueue queue,
  }) : _delegate = delegate,
       _queue = queue;

  final IStreamingDatabaseGateway _delegate;
  final SqlExecutionQueue _queue;

  @override
  bool get hasActiveStream => _delegate.hasActiveStream;

  @override
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 1000,
    int chunkSizeBytes = 1024 * 1024,
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
  }) async {
    final queued = await _queue.submit<bool>(
      () async {
        final streamResult = await _delegate.executeQueryStream(
          query,
          connectionString,
          onChunk,
          fetchSize: fetchSize,
          chunkSizeBytes: chunkSizeBytes,
          executionId: executionId,
          queryTimeout: queryTimeout,
          cancellationToken: cancellationToken,
          cancellationReasonProvider: cancellationReasonProvider,
        );
        return streamResult.fold(
          (_) => const Success(true),
          Failure.new,
        );
      },
      requestId: executionId,
      kind: SqlExecutionKind.streaming,
    );
    return queued.fold(
      (_) => const Success(unit),
      Failure.new,
    );
  }

  @override
  Future<Result<void>> cancelActiveStream({
    String? executionId,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) {
    return _delegate.cancelActiveStream(
      executionId: executionId,
      reason: reason,
    );
  }

  @override
  int get activeStreamCount {
    if (_delegate case final IStreamingGatewayDiagnostics diagnostics) {
      return diagnostics.activeStreamCount;
    }
    return hasActiveStream ? 1 : 0;
  }

  @override
  Map<String, Object?> getStreamingDiagnostics() {
    if (_delegate case final IStreamingGatewayDiagnostics diagnostics) {
      return diagnostics.getStreamingDiagnostics();
    }
    return {
      'has_active_stream': hasActiveStream,
    };
  }
}
