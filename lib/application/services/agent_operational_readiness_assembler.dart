import 'package:plug_agente/application/services/agent_operational_readiness_snapshot.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';

/// Builds a presentation-neutral operational readiness snapshot.
class AgentOperationalReadinessAssembler {
  const AgentOperationalReadinessAssembler();

  AgentOperationalReadinessSnapshot assemble({
    required HubConnectionPhase hubPhase,
    required bool hubConnected,
    required List<ClientTokenSummary> clientTokens,
    String? schedulerIssueReason,
  }) {
    final activeCount = clientTokens.where((token) => !token.isRevoked).length;

    return AgentOperationalReadinessSnapshot(
      hubConnected: hubConnected,
      hubPhase: hubPhase,
      activeClientTokenCount: activeCount,
      schedulerIssueReason: schedulerIssueReason,
    );
  }
}
