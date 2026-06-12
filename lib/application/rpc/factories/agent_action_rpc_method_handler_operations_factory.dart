import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:uuid/uuid.dart';

class AgentActionRpcMethodHandlerOperationsFactory {
  const AgentActionRpcMethodHandlerOperationsFactory();

  AgentActionRpcMethodHandlerOperations create({
    required Uuid uuid,
    required FeatureFlags featureFlags,
    required AgentActionRpcMethodHandlerSupport support,
    IIdempotencyStore? idempotencyStore,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    void Function()? onAgentActionRemoteAuditExecutionCorrelated,
    void Function()? onAgentActionRemoteRateLimited,
    RunAgentActionLocally? runAgentActionLocally,
    RunAgentActionViaRemoteTrigger? runAgentActionViaRemoteTrigger,
    CancelAgentActionExecution? cancelAgentActionExecution,
    GetAgentActionExecution? getAgentActionExecution,
    SliceAgentActionCapturedOutput? sliceAgentActionCapturedOutput,
    GetAgentActionDefinition? getAgentActionDefinition,
    BackfillAgentActionExecutionCorrelation? backfillAgentActionExecutionCorrelation,
    AgentActionRemoteRateLimiter? agentActionRemoteRateLimiter,
    AgentActionRemoteAuthorizationService? agentActionRemoteAuthorization,
    IAgentActionRemoteAuditStore? agentActionRemoteAuditStore,
    AgentActionRuntimeStateGuard? agentActionRuntimeStateGuard,
    AgentRuntimeIdentity? agentRuntimeIdentity,
  }) {
    return AgentActionRpcMethodHandlerOperations(
      uuid: uuid,
      featureFlags: featureFlags,
      support: support,
      idempotencyStore: idempotencyStore,
      dispatchMetrics: dispatchMetrics,
      onAgentActionRemoteAuditExecutionCorrelated: onAgentActionRemoteAuditExecutionCorrelated,
      onAgentActionRemoteRateLimited: onAgentActionRemoteRateLimited,
      runAgentActionLocally: runAgentActionLocally,
      runAgentActionViaRemoteTrigger: runAgentActionViaRemoteTrigger,
      cancelAgentActionExecution: cancelAgentActionExecution,
      getAgentActionExecution: getAgentActionExecution,
      sliceAgentActionCapturedOutput: sliceAgentActionCapturedOutput,
      getAgentActionDefinition: getAgentActionDefinition,
      backfillAgentActionExecutionCorrelation: backfillAgentActionExecutionCorrelation,
      agentActionRemoteRateLimiter: agentActionRemoteRateLimiter,
      agentActionRemoteAuthorization: agentActionRemoteAuthorization,
      agentActionRemoteAuditStore: agentActionRemoteAuditStore,
      agentActionRuntimeStateGuard: agentActionRuntimeStateGuard,
      agentRuntimeIdentity: agentRuntimeIdentity,
    );
  }
}
