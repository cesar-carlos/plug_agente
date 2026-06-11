import 'package:plug_agente/domain/domain.dart' show IAgentActionRepository;
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart' show IAgentActionRepository;
import 'package:plug_agente/domain/repositories/repositories.dart' show IAgentActionRepository;

/// Stable diagnostic `reason` strings for agent action runtime lifecycle transitions
/// and subsystem readiness surfaced on authorization failures.
abstract final class AgentActionRuntimeStateConstants {
  /// Default cap when [IAgentActionRepository.listExecutions] is called without
  /// an explicit `limit`. Pass `limit <= 0` to request no cap.
  static const int listExecutionsDefaultLimit = 500;

  static int? resolveListExecutionsLimit(int? limit) {
    if (limit == null) {
      return listExecutionsDefaultLimit;
    }
    if (limit <= 0) {
      return null;
    }
    return limit;
  }

  static const String shutdownReason = 'shutdown';

  static const String bootstrapReason = 'bootstrap';

  static const String appRootDisposeReason = 'app_root_dispose';

  static const String agentActionsStartingReason = 'agent_actions_starting';

  static const String agentActionsDrainingReason = 'agent_actions_draining';

  static const String enteringMaintenanceModeReason = 'entering_maintenance_mode';

  static const String remoteProtocolRollbackReason = 'remote_protocol_rollback';

  static const String agentActionsDegradedReason = 'agent_actions_degraded';

  static const String deferredBootstrapSchedulerFailedReason = 'deferred_bootstrap_scheduler_failed';

  static const String deferredBootstrapCriticalFailureReason = 'deferred_bootstrap_critical_failure';

  static const String subsystemReadyReason = 'ready';
}
