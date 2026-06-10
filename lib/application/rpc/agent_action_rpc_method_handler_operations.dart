import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_audit_operations.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_execution_operations.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_support.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_remote_infrastructure.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:uuid/uuid.dart';

export 'agent_action_rpc_method_handler_support.dart';

class AgentActionRpcMethodHandlerOperations {
  AgentActionRpcMethodHandlerOperations({
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
    final infrastructure = AgentActionRpcRemoteInfrastructure(
      featureFlags: featureFlags,
      support: support,
      idempotencyStore: idempotencyStore,
      backfillAgentActionExecutionCorrelation: backfillAgentActionExecutionCorrelation,
      agentActionRemoteRateLimiter: agentActionRemoteRateLimiter,
      agentActionRemoteAuthorization: agentActionRemoteAuthorization,
      agentActionRuntimeStateGuard: agentActionRuntimeStateGuard,
      agentRuntimeIdentity: agentRuntimeIdentity,
      onAgentActionRemoteRateLimited: onAgentActionRemoteRateLimited,
    );
    final audit = AgentActionRpcAuditOperations(
      uuid: uuid,
      featureFlags: featureFlags,
      infrastructure: infrastructure,
      agentActionRemoteAuditStore: agentActionRemoteAuditStore,
      dispatchMetrics: dispatchMetrics,
      agentRuntimeIdentity: agentRuntimeIdentity,
      onAgentActionRemoteAuditExecutionCorrelated: onAgentActionRemoteAuditExecutionCorrelated,
    );
    _execution = AgentActionRpcExecutionOperations(
      infrastructure: infrastructure,
      audit: audit,
      runAgentActionLocally: runAgentActionLocally,
      runAgentActionViaRemoteTrigger: runAgentActionViaRemoteTrigger,
      cancelAgentActionExecution: cancelAgentActionExecution,
      getAgentActionExecution: getAgentActionExecution,
      sliceAgentActionCapturedOutput: sliceAgentActionCapturedOutput,
      getAgentActionDefinition: getAgentActionDefinition,
    );
  }

  late final AgentActionRpcExecutionOperations _execution;

  Future<RpcResponse> handleAgentActionRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _execution.handleAgentActionRun(request, agentId, clientToken);

  Future<RpcResponse> handleAgentActionValidateRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _execution.handleAgentActionValidateRun(request, agentId, clientToken);

  Future<RpcResponse> handleAgentActionCancel(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _execution.handleAgentActionCancel(request, agentId, clientToken);

  Future<RpcResponse> handleAgentActionGetExecution(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _execution.handleAgentActionGetExecution(request, agentId, clientToken);
}
