import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

class RpcDispatchMetricsCollector implements IRpcDispatchMetricsCollector {
  RpcDispatchMetricsCollector(this._metrics);

  final MetricsCollector _metrics;

  @override
  void recordSqlExecuteStreamingChunksResponse() => _metrics.recordRpcSqlExecuteStreamingChunksResponse();

  @override
  void recordSqlExecuteStreamingFromDbResponse() => _metrics.recordRpcSqlExecuteStreamingFromDbResponse();

  @override
  void recordSqlExecuteMaterializedResponse() => _metrics.recordRpcSqlExecuteMaterializedResponse();

  @override
  void recordStreamTerminalCompleteEmitted() => _metrics.recordRpcStreamTerminalCompleteEmitted();

  @override
  void recordStreamTerminalCompleteFailed() => _metrics.recordRpcStreamTerminalCompleteFailed();

  @override
  void recordRpcResponseAckRetry() => _metrics.recordRpcResponseAckRetry();

  @override
  void recordRpcResponseAckFallbackWithoutAck() => _metrics.recordRpcResponseAckFallbackWithoutAck();

  @override
  void recordClientTokenGetPolicySuccess() => _metrics.recordClientTokenGetPolicySuccess();

  @override
  void recordClientTokenGetPolicyFailure(Failure failure) =>
      _metrics.recordClientTokenGetPolicyFailure(failure);

  @override
  void recordClientTokenGetPolicyRateLimited() => _metrics.recordClientTokenGetPolicyRateLimited();
}
