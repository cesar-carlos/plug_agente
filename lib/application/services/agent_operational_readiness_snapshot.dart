import 'package:meta/meta.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';

@immutable
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

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentOperationalReadinessSnapshot &&
            hubConnected == other.hubConnected &&
            hubPhase == other.hubPhase &&
            activeClientTokenCount == other.activeClientTokenCount &&
            schedulerIssueReason == other.schedulerIssueReason;
  }

  @override
  int get hashCode => Object.hash(
    hubConnected,
    hubPhase,
    activeClientTokenCount,
    schedulerIssueReason,
  );
}
