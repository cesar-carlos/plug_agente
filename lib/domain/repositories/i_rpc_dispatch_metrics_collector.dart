import 'package:plug_agente/domain/errors/failures.dart';

/// Optional counters for RPC `sql.execute` result paths (observability).
abstract class IRpcDispatchMetricsCollector {
  void recordSqlExecuteStreamingChunksResponse();

  void recordSqlExecuteStreamingFromDbResponse();

  void recordSqlExecuteMaterializedResponse();

  /// Incremented each time an `rpc:complete` with `terminal_status` is emitted.
  void recordStreamTerminalCompleteEmitted();

  /// Incremented when emitting a terminal `rpc:complete` itself throws.
  void recordStreamTerminalCompleteFailed();

  /// Incremented on each ACK retry for a pending `rpc:response`.
  void recordRpcResponseAckRetry();

  /// Incremented when an `rpc:response` is sent without waiting for ACK
  /// because the ACK mechanism is unavailable or timed out.
  void recordRpcResponseAckFallbackWithoutAck();

  void recordClientTokenGetPolicySuccess();

  void recordClientTokenGetPolicyFailure(Failure failure);

  void recordClientTokenGetPolicyRateLimited();
}
