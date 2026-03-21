import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

class RpcDispatchMetricsCollector implements IRpcDispatchMetricsCollector {
  RpcDispatchMetricsCollector(this._metrics);

  final MetricsCollector _metrics;

  @override
  void recordSqlExecuteStreamingChunksResponse() =>
      _metrics.recordRpcSqlExecuteStreamingChunksResponse();

  @override
  void recordSqlExecuteStreamingFromDbResponse() =>
      _metrics.recordRpcSqlExecuteStreamingFromDbResponse();

  @override
  void recordSqlExecuteMaterializedResponse() =>
      _metrics.recordRpcSqlExecuteMaterializedResponse();

  @override
  void recordRpcStreamTerminalCompleteEmitted() =>
      _metrics.recordRpcStreamTerminalCompleteEmitted();

  @override
  void recordRpcStreamTerminalCompleteFailed() =>
      _metrics.recordRpcStreamTerminalCompleteFailed();
}
