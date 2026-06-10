import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';

/// Wraps a streaming gateway with the shared [SqlExecutionQueue] so ODBC
/// streaming connect/setup is bounded by SQL queue backpressure limits.
///
/// The queue worker is released after connect and stream registration; the
/// stream body continues under the direct ODBC connection limiter only.
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
    void Function()? onSetupComplete,
  }) async {
    final lifecycleToken = cancellationToken ?? CancellationToken();
    final queued = await _queue.submitWithReleasableWorker<bool>(
      (releaseWorker) async {
        final streamResult = await _delegate.executeQueryStream(
          query,
          connectionString,
          onChunk,
          fetchSize: fetchSize,
          chunkSizeBytes: chunkSizeBytes,
          executionId: executionId,
          queryTimeout: queryTimeout,
          cancellationToken: lifecycleToken,
          cancellationReasonProvider: cancellationReasonProvider,
          onSetupComplete: () {
            releaseWorker();
            onSetupComplete?.call();
          },
        );
        return streamResult.fold(
          (_) => const Success(true),
          Failure.new,
        );
      },
      requestId: executionId,
      kind: SqlExecutionKind.streaming,
      cooperativeCancellationToken: lifecycleToken,
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
