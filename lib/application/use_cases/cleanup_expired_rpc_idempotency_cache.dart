import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:result_dart/result_dart.dart';

class CleanupExpiredRpcIdempotencyCache {
  const CleanupExpiredRpcIdempotencyCache(
    this._store, {
    AgentActionExecutionMetricsCollector? metrics,
  }) : _metrics = metrics;

  final IIdempotencyStore _store;
  final AgentActionExecutionMetricsCollector? _metrics;

  Future<Result<int>> call({DateTime? referenceTime}) async {
    try {
      final removed = await _store.purgeExpiredEntries(referenceTime: referenceTime);
      _metrics?.recordRpcIdempotencyCachePurge(removed);
      return Success(removed);
    } on Object catch (error, stackTrace) {
      return Failure(
        ServerFailure.withContext(
          message: 'Failed to purge expired RPC idempotency cache entries',
          cause: error,
          context: {
            'operation': 'cleanup_expired_rpc_idempotency_cache',
            'stack_trace': stackTrace.toString(),
          },
        ),
      );
    }
  }
}
