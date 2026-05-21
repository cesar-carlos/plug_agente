import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class CleanupExpiredAgentActionRemoteAudit {
  const CleanupExpiredAgentActionRemoteAudit(
    this._store, {
    required Duration retention,
    this.batchLimit = 2000,
    this.maxBatches = 50,
    AgentActionExecutionMetricsCollector? metrics,
  }) : _retention = retention,
       _metrics = metrics;

  final IAgentActionRemoteAuditStore _store;
  final Duration _retention;
  final AgentActionExecutionMetricsCollector? _metrics;
  final int batchLimit;
  final int maxBatches;

  Future<Result<int>> call({DateTime? referenceTime}) async {
    try {
      final nowUtc = (referenceTime ?? DateTime.now()).toUtc();
      final cutoffUtc = nowUtc.subtract(_retention);
      var total = 0;
      for (var batch = 0; batch < maxBatches; batch++) {
        final removed = await _store.deleteWhereOccurredBefore(
          cutoffUtc: cutoffUtc,
          limit: batchLimit,
        );
        if (removed <= 0) {
          break;
        }
        total += removed;
      }
      _metrics?.recordRemoteAuditPurge(total);
      return Success(total);
    } on Object catch (error, stackTrace) {
      return Failure(
        ServerFailure.withContext(
          message: 'Failed to purge old agent action remote audit rows',
          cause: error,
          context: {
            'operation': 'cleanup_expired_agent_action_remote_audit',
            'stack_trace': stackTrace.toString(),
          },
        ),
      );
    }
  }
}
