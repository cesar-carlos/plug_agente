import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class CleanupAgentActionCapturedOutput {
  CleanupAgentActionCapturedOutput(
    this._repository, {
    Duration? retention,
    AgentActionExecutionMetricsCollector? metrics,
  }) : retention = retention ?? ConnectionConstants.agentActionCapturedOutputRetention,
       _metrics = metrics;

  final IAgentActionRepository _repository;
  final Duration retention;
  final AgentActionExecutionMetricsCollector? _metrics;

  Future<Result<int>> call({
    DateTime? now,
  }) async {
    final referenceTime = now ?? DateTime.now();
    final result = await _repository.clearCapturedOutputOlderThan(
      olderThan: referenceTime.subtract(retention),
    );
    if (result.isSuccess()) {
      _metrics?.recordCapturedOutputCleared(result.getOrThrow());
    }
    return result;
  }
}
