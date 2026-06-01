import 'package:plug_agente/domain/errors/failures.dart';

/// Optional counters for RPC `sql.execute` result paths (observability).
abstract class IRpcDispatchMetricsCollector {
  void recordSqlExecuteStreamingChunksResponse();

  void recordSqlExecuteStreamingFromDbResponse();

  void recordSqlExecuteAutoStreamingFromDbResponse();

  void recordSqlExecutePreferDbStreamingResponse();

  void recordSqlExecuteAllowlistDbStreamingResponse();

  void recordSqlExecuteDbStreamingSkipped(String reason);

  void recordSqlExecuteMaterializedResponse();

  /// Incremented each time an `rpc:complete` with `terminal_status` is emitted.
  void recordStreamTerminalCompleteEmitted();

  /// Incremented when emitting a terminal `rpc:complete` itself throws.
  void recordStreamTerminalCompleteFailed();

  /// Incremented on each ACK retry for a pending `rpc:response`.
  void recordRpcResponseAckRetry();

  /// Incremented when an `rpc:response` ACK is delivered successfully.
  void recordRpcResponseAckDelivered();

  /// Incremented when an ACK delivery loop is abandoned because socket or
  /// connection generation changed before completion.
  void recordRpcResponseAckAbortedConnectionChange();

  /// Incremented when an `rpc:response` is sent without waiting for ACK
  /// because the ACK mechanism is unavailable or timed out.
  void recordRpcResponseAckFallbackWithoutAck();

  /// Incremented when `sql.execute` intentionally bypasses Socket.IO ACK to
  /// keep the inbound RPC flow non-blocking.
  void recordRpcResponseAckSkippedSqlExecute();

  /// Incremented when `sql.executeBatch` intentionally bypasses Socket.IO ACK
  /// to keep the inbound RPC flow non-blocking.
  void recordRpcResponseAckSkippedSqlExecuteBatch();

  void recordClientTokenGetPolicySuccess();

  void recordClientTokenGetPolicyFailure(Failure failure);

  void recordClientTokenGetPolicyRateLimited();

  /// Counts remote `agent.action.*` outcomes. [rpcMethod] must be a published
  /// remote agent action JSON-RPC method name; unknown values are ignored.
  void recordRpcAgentActionRemoteOutcome(String rpcMethod, {required bool success});

  /// Counts `agent.action.*` calls rejected because they were sent as JSON-RPC
  /// notifications (no `id`). Does not increment success/error RPC counters.
  void recordRpcAgentActionNotificationRejected(String rpcMethod);

  void recordRpcMethodConcurrencyLimited(String rpcMethod);

  void recordSqlStreamCancelled(String reason);

  void recordSqlStreamCancelFailed(String reason);
}
