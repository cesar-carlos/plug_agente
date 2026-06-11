import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/services/agent_action_captured_output_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_execution_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_remote_audit_periodic_purge.dart';
import 'package:plug_agente/application/services/elevated_bridge_artifacts_periodic_purge.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_elevated_bridge_artifacts.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_rpc_idempotency_cache.dart';
import 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

final class AgentActionsBootPhasesDependencies {
  const AgentActionsBootPhasesDependencies({
    required this.reconcileAgentActionExecutions,
    required this.cleanupExpiredRpcIdempotencyCache,
    required this.rpcIdempotencyCachePeriodicPurge,
    required this.cleanupExpiredAgentActionRemoteAudit,
    required this.agentActionRemoteAuditPeriodicPurge,
    required this.cleanupAgentActionExecutions,
    required this.agentActionExecutionPeriodicPurge,
    required this.agentActionTriggerScheduler,
    this.elevatedActionRunnerReadiness,
    this.globalStorageContext,
    this.cleanupExpiredElevatedBridgeArtifacts,
    this.elevatedBridgeArtifactsPeriodicPurge,
    this.cleanupAgentActionCapturedOutput,
    this.agentActionCapturedOutputPeriodicPurge,
  });

  final ReconcileAgentActionExecutions reconcileAgentActionExecutions;
  final CleanupExpiredRpcIdempotencyCache cleanupExpiredRpcIdempotencyCache;
  final RpcIdempotencyCachePeriodicPurge rpcIdempotencyCachePeriodicPurge;
  final CleanupExpiredAgentActionRemoteAudit cleanupExpiredAgentActionRemoteAudit;
  final AgentActionRemoteAuditPeriodicPurge agentActionRemoteAuditPeriodicPurge;
  final CleanupAgentActionExecutions cleanupAgentActionExecutions;
  final AgentActionExecutionPeriodicPurge agentActionExecutionPeriodicPurge;
  final AgentActionTriggerScheduler agentActionTriggerScheduler;
  final ElevatedActionRunnerReadinessService? elevatedActionRunnerReadiness;
  final GlobalStorageContext? globalStorageContext;
  final CleanupExpiredElevatedBridgeArtifacts? cleanupExpiredElevatedBridgeArtifacts;
  final ElevatedBridgeArtifactsPeriodicPurge? elevatedBridgeArtifactsPeriodicPurge;
  final CleanupAgentActionCapturedOutput? cleanupAgentActionCapturedOutput;
  final AgentActionCapturedOutputPeriodicPurge? agentActionCapturedOutputPeriodicPurge;
}
