/// Stable diagnostic `reason` strings for agent action runtime lifecycle transitions
/// and subsystem readiness surfaced on authorization failures.
abstract final class AgentActionRuntimeStateConstants {
  static const String shutdownReason = 'shutdown';

  static const String bootstrapReason = 'bootstrap';

  static const String appRootDisposeReason = 'app_root_dispose';

  static const String agentActionsStartingReason = 'agent_actions_starting';

  static const String agentActionsDrainingReason = 'agent_actions_draining';

  static const String enteringMaintenanceModeReason = 'entering_maintenance_mode';

  static const String remoteProtocolRollbackReason = 'remote_protocol_rollback';

  static const String agentActionsDegradedReason = 'agent_actions_degraded';

  static const String subsystemReadyReason = 'ready';
}
