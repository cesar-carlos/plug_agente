import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';

class AgentOperationalReadinessSnapshot {
  const AgentOperationalReadinessSnapshot({
    required this.hubConnected,
    required this.hubPhase,
    required this.activeClientTokenCount,
    this.schedulerIssueReason,
  });

  final bool hubConnected;
  final HubConnectionPhase hubPhase;
  final int activeClientTokenCount;
  final String? schedulerIssueReason;

  bool get hasSchedulerIssue => schedulerIssueReason != null && schedulerIssueReason!.isNotEmpty;
}
