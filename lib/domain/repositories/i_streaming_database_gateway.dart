import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:result_dart/result_dart.dart';

/// Gateway para execução de queries em streaming.
///
/// Permite processar queries grandes que retornam milhões de linhas
/// sem carregar tudo na memória de uma vez.
abstract class IStreamingDatabaseGateway {
  /// Whether there is an active streaming execution that can be cancelled.
  bool get hasActiveStream;

  /// Executa query em streaming, processando em chunks.
  ///
  /// [onChunk] é chamado para cada lote de linhas processado (pode ser async
  /// para alinhar com framing de socket sem bloquear a isolate principal).
  /// [fetchSize] é o número de linhas buscadas por vez.
  /// [chunkSizeBytes] é o tamanho aproximado em bytes de cada chunk.
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize,
    int chunkSizeBytes,
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
    Future<void> Function(StreamingWireChunk chunk)? onWireChunk,
    Map<String, dynamic>? parameters,
    bool columnarWireOnly = false,

    /// Invoked after ODBC connect and stream registration succeed, before the
    /// first result chunk is consumed. Used by the queued streaming gateway
    /// to release the SQL queue worker while the stream body continues.
    void Function()? onSetupComplete,
  });

  /// Streams ODBC multi-result batches one item at a time without materializing
  /// the full multi-result envelope first.
  Future<Result<void>> executeMultiResultQueryStream(
    String query,
    String connectionString,
    Future<void> Function(StreamingWireChunk chunk) onWireChunk, {
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
    void Function()? onSetupComplete,
  });

  /// Cancela o streaming ativo no runtime ODBC.
  ///
  /// Deve interromper a operação em andamento e liberar recursos.
  Future<Result<void>> cancelActiveStream({
    String? executionId,
    StreamingCancelReason reason = StreamingCancelReason.user,
  });
}

/// Optional diagnostics surface for streaming gateway health reporting.
abstract class IStreamingGatewayDiagnostics {
  int get activeStreamCount;

  Map<String, Object?> getStreamingDiagnostics();
}
