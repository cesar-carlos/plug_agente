import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

final class AgentActionHistoryCursor {
  const AgentActionHistoryCursor(this.requestedAt, this.executionId);
  final DateTime requestedAt;
  final String executionId;
}

abstract interface class IAgentActionHistoryPage {
  Future<Result<List<AgentActionExecution>>> listExecutionPage({
    required int limit,
    AgentActionHistoryCursor? after,
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
  });
}
