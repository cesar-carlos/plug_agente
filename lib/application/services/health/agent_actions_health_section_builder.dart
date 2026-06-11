import 'package:path/path.dart' as p;
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/services/health/health_metric_helpers.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';

final class AgentActionsHealthSectionBuilder {
  const AgentActionsHealthSectionBuilder({
    FeatureFlags? featureFlags,
    AgentActionLocalRunnerRegistry? agentActionRunnerRegistry,
    AgentActionRuntimeStateGuard? agentActionRuntimeStateGuard,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    AgentActionRetentionSettings? agentActionRetentionSettings,
    AgentActionTriggerScheduler? agentActionTriggerScheduler,
    IAgentActionSchedulerInstanceLock? agentActionSchedulerInstanceLock,
    GlobalStorageContext? globalStorageContext,
    IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics,
  }) : _featureFlags = featureFlags,
       _agentActionRunnerRegistry = agentActionRunnerRegistry,
       _agentActionRuntimeStateGuard = agentActionRuntimeStateGuard,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _agentActionRetentionSettings = agentActionRetentionSettings,
       _agentActionTriggerScheduler = agentActionTriggerScheduler,
       _agentActionSchedulerInstanceLock = agentActionSchedulerInstanceLock,
       _globalStorageContext = globalStorageContext,
       _comObjectInvocationDiagnostics = comObjectInvocationDiagnostics;

  final FeatureFlags? _featureFlags;
  final AgentActionLocalRunnerRegistry? _agentActionRunnerRegistry;
  final AgentActionRuntimeStateGuard? _agentActionRuntimeStateGuard;
  final ElevatedActionRunnerReadinessService? _elevatedRunnerReadiness;
  final AgentActionRetentionSettings? _agentActionRetentionSettings;
  final AgentActionTriggerScheduler? _agentActionTriggerScheduler;
  final IAgentActionSchedulerInstanceLock? _agentActionSchedulerInstanceLock;
  final GlobalStorageContext? _globalStorageContext;
  final IComObjectInvocationDiagnostics? _comObjectInvocationDiagnostics;

  Map<String, Object?>? build(Map<String, Object?> metrics) {
    final flags = _featureFlags;
    if (flags == null) {
      return null;
    }

    final enabled = flags.enableAgentActions;
    final snapshot = _agentActionRuntimeStateGuard?.snapshot;
    final supportedTypes = _supportedTypeNames();
    final unavailableTypes =
        snapshot?.unavailableActionTypes.map((AgentActionType type) => type.name).toList(growable: false) ??
        const <String>[];
    final String statusName;
    if (!enabled) {
      statusName = AgentActionSubsystemStatus.disabled.name;
    } else {
      statusName = snapshot?.status.name ?? AgentActionSubsystemStatus.ready.name;
    }

    final queueCounters = <String, Object?>{
      'concurrency_reject_total': healthMetricInt(metrics, 'agent_action_queue_concurrency_reject'),
      'concurrency_ignore_total': healthMetricInt(metrics, 'agent_action_queue_concurrency_ignore'),
      'depth_full_total': healthMetricInt(metrics, 'agent_action_queue_depth_full'),
      'pending_enqueued_total': healthMetricInt(metrics, 'agent_action_queue_pending_enqueued'),
      'idempotent_replay_total': healthMetricInt(metrics, 'agent_action_queue_idempotent_replay'),
      'run_started_total': healthMetricInt(metrics, 'agent_action_queue_run_started'),
      'pending_wait_timeout_total': healthMetricInt(metrics, 'agent_action_queue_pending_wait_timeout'),
      'pending_cancelled_total': healthMetricInt(metrics, 'agent_action_queue_pending_cancelled'),
    };

    final queueWait = <String, Object?>{
      'avg_time_ms': (metrics['agent_action_queue_wait_avg_time_ms'] as num?)?.toDouble() ?? 0.0,
      'p95_time_ms': healthMetricInt(metrics, 'agent_action_queue_wait_p95_time_ms'),
      'p99_time_ms': healthMetricInt(metrics, 'agent_action_queue_wait_p99_time_ms'),
      'max_recent_time_ms': healthMetricInt(metrics, 'agent_action_queue_wait_max_recent_time_ms'),
      'sample_count': healthMetricInt(metrics, 'agent_action_queue_wait_sample_count'),
    };

    final remoteRpc = <String, Object?>{
      'run_success_total': healthMetricInt(metrics, 'rpc_remote_agent_action_run_success'),
      'run_error_total': healthMetricInt(metrics, 'rpc_remote_agent_action_run_error'),
      'run_notification_rejected_total': healthMetricInt(metrics, 'rpc_remote_agent_action_run_notification_rejected'),
      'validate_run_success_total': healthMetricInt(metrics, 'rpc_remote_agent_action_validate_run_success'),
      'validate_run_error_total': healthMetricInt(metrics, 'rpc_remote_agent_action_validate_run_error'),
      'validate_run_notification_rejected_total': healthMetricInt(
        metrics,
        'rpc_remote_agent_action_validate_run_notification_rejected',
      ),
      'cancel_success_total': healthMetricInt(metrics, 'rpc_remote_agent_action_cancel_success'),
      'cancel_error_total': healthMetricInt(metrics, 'rpc_remote_agent_action_cancel_error'),
      'cancel_notification_rejected_total': healthMetricInt(
        metrics,
        'rpc_remote_agent_action_cancel_notification_rejected',
      ),
      'get_execution_success_total': healthMetricInt(metrics, 'rpc_remote_agent_action_get_execution_success'),
      'get_execution_error_total': healthMetricInt(metrics, 'rpc_remote_agent_action_get_execution_error'),
      'get_execution_notification_rejected_total': healthMetricInt(
        metrics,
        'rpc_remote_agent_action_get_execution_notification_rejected',
      ),
      'batch_read_limit_rejected_total': healthMetricInt(
        metrics,
        'rpc_remote_agent_action_batch_read_limit_rejected',
      ),
    };

    final executionCounters = <String, Object?>{
      'terminal_succeeded_total': healthMetricInt(metrics, 'agent_action_execution_terminal_succeeded'),
      'terminal_failed_total': healthMetricInt(metrics, 'agent_action_execution_terminal_failed'),
      'terminal_skipped_total': healthMetricInt(metrics, 'agent_action_execution_terminal_skipped'),
      'terminal_cancelled_total': healthMetricInt(metrics, 'agent_action_execution_terminal_cancelled'),
      'terminal_killed_total': healthMetricInt(metrics, 'agent_action_execution_terminal_killed'),
      'terminal_timed_out_total': healthMetricInt(metrics, 'agent_action_execution_terminal_timed_out'),
      'terminal_interrupted_total': healthMetricInt(metrics, 'agent_action_execution_terminal_interrupted'),
      'terminal_unknown_total': healthMetricInt(metrics, 'agent_action_execution_terminal_unknown'),
      'remote_permission_denied_total': healthMetricInt(metrics, 'agent_action_remote_permission_denied'),
      'local_authorization_denied_total': healthMetricInt(metrics, 'agent_action_local_authorization_denied'),
      'remote_rate_limited_total': healthMetricInt(metrics, 'agent_action_remote_rate_limited'),
      'history_purge_total': healthMetricInt(metrics, 'agent_action_execution_history_purge'),
      'remote_audit_purge_total': healthMetricInt(metrics, 'agent_action_remote_audit_purge'),
      'rpc_idempotency_cache_purge_total': healthMetricInt(metrics, 'agent_action_rpc_idempotency_cache_purge'),
      'elevated_bridge_artifacts_purge_total': healthMetricInt(metrics, 'agent_action_elevated_bridge_artifacts_purge'),
      'remote_audit_execution_correlated_total': healthMetricInt(
        metrics,
        'agent_action_remote_audit_execution_correlated',
      ),
      'cancel_kill_failed_total': healthMetricInt(metrics, 'agent_action_cancel_kill_failed'),
      'cancel_kill_permission_denied_total': healthMetricInt(
        metrics,
        'agent_action_cancel_kill_permission_denied',
      ),
      'cancel_process_not_active_total': healthMetricInt(metrics, 'agent_action_cancel_process_not_active'),
      'cancel_process_id_mismatch_total': healthMetricInt(metrics, 'agent_action_cancel_process_id_mismatch'),
      'cancel_process_identity_mismatch_total': healthMetricInt(
        metrics,
        'agent_action_cancel_process_identity_mismatch',
      ),
      'cancel_process_identity_unavailable_total': healthMetricInt(
        metrics,
        'agent_action_cancel_process_identity_unavailable',
      ),
      'captured_stdout_truncated_total': healthMetricInt(metrics, 'agent_action_captured_output_stdout_truncated'),
      'captured_stderr_truncated_total': healthMetricInt(metrics, 'agent_action_captured_output_stderr_truncated'),
      'captured_stdout_bytes_total': healthMetricInt(metrics, 'agent_action_captured_output_stdout_bytes'),
      'captured_stderr_bytes_total': healthMetricInt(metrics, 'agent_action_captured_output_stderr_bytes'),
      'captured_output_cleared_total': healthMetricInt(metrics, 'agent_action_captured_output_cleared'),
      'elevated_status_file_terminal_total': healthMetricInt(metrics, 'agent_action_elevated_status_file_terminal'),
      'elevated_status_file_wait_timeout_total': healthMetricInt(
        metrics,
        'agent_action_elevated_status_file_wait_timeout',
      ),
    };

    final executionDurationMs = <String, Object?>{
      'avg_time_ms': (metrics['agent_action_execution_avg_time_ms'] as num?)?.toDouble() ?? 0.0,
      'p95_time_ms': healthMetricInt(metrics, 'agent_action_execution_p95_time_ms'),
      'p99_time_ms': healthMetricInt(metrics, 'agent_action_execution_p99_time_ms'),
      'max_recent_time_ms': healthMetricInt(metrics, 'agent_action_execution_max_recent_time_ms'),
      'sample_count': healthMetricInt(metrics, 'agent_action_execution_sample_count'),
    };

    return <String, Object?>{
      'enabled': enabled,
      'remote_enabled': flags.enableRemoteAgentActions,
      'remote_ad_hoc_enabled': flags.enableRemoteAdHocAgentActions,
      'elevated_enabled': flags.enableElevatedAgentActions,
      'elevated_runner_configured': _elevatedRunnerReadiness?.isConfigured ?? false,
      'elevated_runner_degraded': _elevatedRunnerReadiness?.isDegraded ?? false,
      if (_comObjectInvocationDiagnostics case final IComObjectInvocationDiagnostics comDiagnostics) ...{
        'com_object_handlers_registered_count': comDiagnostics.registeredHandlerCount,
        'com_object_invocation_ready': comDiagnostics.registeredHandlerCount > 0,
      },
      'maintenance_mode': flags.enableAgentActionsMaintenanceMode,
      'maintenance_strict_mode': flags.enableAgentActionsMaintenanceStrictMode,
      'remote_audit_enabled': flags.enableAgentActionRemoteAudit,
      'status': statusName,
      'supported_types': supportedTypes,
      'unavailable_types': unavailableTypes,
      'queue_counters': queueCounters,
      'queue_wait_ms': queueWait,
      'execution_counters': executionCounters,
      'execution_duration_ms': executionDurationMs,
      'remote_rpc_counters': remoteRpc,
      if (_buildRetentionHealth() case final Map<String, Object?> retention) 'retention': retention,
      if (_buildSchedulerHealth() case final Map<String, Object?> scheduler) 'scheduler': scheduler,
    };
  }

  Map<String, Object?>? _buildSchedulerHealth() {
    final scheduler = _agentActionTriggerScheduler;
    if (scheduler == null) {
      return null;
    }

    final lock = _agentActionSchedulerInstanceLock;

    final storageContext = _globalStorageContext;
    final lockFilePath = storageContext == null || scheduler.lastStartIssueReason == null
        ? null
        : p.join(storageContext.appDirectoryPath, AgentActionTriggerConstants.schedulerLockFileName);

    return <String, Object?>{
      'started': scheduler.isTemporalSchedulerStarted,
      'bootstrap_disabled': scheduler.isBootstrapDisabled,
      'temporal_timer_count': scheduler.scheduledTimerCount,
      if (lock != null) 'instance_lock_held': lock.isHeld,
      if (scheduler.lastStartIssueReason case final String reason) 'last_start_issue_reason': reason,
      if (scheduler.lastStartIssueReason != null && lockFilePath != null) 'lock_file_path': lockFilePath,
    };
  }

  Map<String, Object?>? _buildRetentionHealth() {
    final settings = _agentActionRetentionSettings;
    if (settings == null) {
      return null;
    }

    return <String, Object?>{
      'execution_days': settings.executionRetentionDays,
      'remote_audit_days': settings.remoteAuditRetentionDays,
      'captured_output_hours': settings.capturedOutputRetentionHours,
      'persisted_override': settings.hasPersistedOverrides,
      'rpc_idempotency_ttl_seconds': settings.agentActionRpcIdempotencyTtl.inSeconds,
    };
  }

  List<String> _supportedTypeNames() {
    final registry = _agentActionRunnerRegistry;
    if (registry == null) {
      return const <String>['commandLine'];
    }
    final names = registry.supportedTypes.map((AgentActionType type) => type.name).toList(growable: false);
    return names.isEmpty ? const <String>['commandLine'] : names;
  }
}
