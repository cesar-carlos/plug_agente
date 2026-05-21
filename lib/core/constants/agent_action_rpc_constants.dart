import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';

/// Limits and JSON-RPC method names for remote agent actions (`agent.action.*`).
abstract final class AgentActionRpcConstants {
  /// Reserved JSON-RPC error band for future dedicated agent-action codes.
  /// MVP 3 reuses shared codes (-32001..-32015, -32602) with `category: action`.
  static const int reservedDomainErrorCodeMin = -32299;

  static const int reservedDomainErrorCodeMax = -32200;

  /// Prefix for JSON-RPC methods in the remote agent action family (`agent.action.*`).
  static const String remoteAgentActionMethodPrefix = 'agent.action.';

  /// JSON-RPC method name: remote execute (`RpcMethodDispatcher` switch must match).
  static const String agentActionRunRpcMethodName = 'agent.action.run';

  /// JSON-RPC method name: remote validate-only run (`RpcMethodDispatcher` switch must match).
  static const String agentActionValidateRunRpcMethodName = 'agent.action.validateRun';

  /// JSON-RPC method name: remote cancel (`RpcMethodDispatcher` switch must match).
  static const String agentActionCancelRpcMethodName = 'agent.action.cancel';

  /// JSON-RPC method name: remote execution lookup (`RpcMethodDispatcher` switch must match).
  static const String agentActionGetExecutionRpcMethodName = 'agent.action.getExecution';

  /// Sentinel `SELECT` targets for client-token authorization when
  /// `enableClientTokenAuthorization` is on.
  /// Hub policies must grant **read** on the matching synthetic resource name (table segment).
  static const String clientTokenAuthorizationSqlAgentActionRun = 'SELECT * FROM plug_agent_action_run';

  static const String clientTokenAuthorizationSqlAgentActionValidateRun =
      'SELECT * FROM plug_agent_action_validate_run';

  static const String clientTokenAuthorizationSqlAgentActionCancel = 'SELECT * FROM plug_agent_action_cancel';

  static const String clientTokenAuthorizationSqlAgentActionGetExecution =
      'SELECT * FROM plug_agent_action_get_execution';

  /// Stable order for `agentActions.supportedMethods` and capability payloads.
  static const List<String> remotePublishedRpcMethodNamesOrdered = <String>[
    agentActionRunRpcMethodName,
    agentActionValidateRunRpcMethodName,
    agentActionCancelRpcMethodName,
    agentActionGetExecutionRpcMethodName,
  ];

  /// Remote JSON-RPC method names under `agent.action.*` published in
  /// `docs/communication/openrpc.json` and handled by `RpcMethodDispatcher`.
  static final Set<String> remotePublishedRpcMethodNames = Set<String>.from(remotePublishedRpcMethodNamesOrdered);

  /// Methods rejected when embedded in a JSON-RPC batch (MVP policy).
  static const List<String> jsonRpcBatchDisallowedAgentActionMethodsOrdered = <String>[
    agentActionRunRpcMethodName,
    agentActionCancelRpcMethodName,
  ];

  static final Set<String> jsonRpcBatchDisallowedAgentActionMethods = Set<String>.from(
    jsonRpcBatchDisallowedAgentActionMethodsOrdered,
  );

  /// OAuth-style scopes for client-token policy (`agent_actions.*`), aligned with
  /// `agentActions.authorizationScopes` in registration capabilities.
  static const String agentActionsRunScope = 'agent_actions.run';

  static const String agentActionsValidateRunScope = 'agent_actions.validate_run';

  static const String agentActionsCancelScope = 'agent_actions.cancel';

  static const String agentActionsReadExecutionScope = 'agent_actions.read_execution';

  /// Wildcard scope accepted by policy checks when the hub grants all agent action RPCs.
  static const String agentActionsWildcardScope = 'agent_actions.*';

  /// Stable order as advertised in `agentActions.authorizationScopes`.
  static const List<String> remotePublishedAuthorizationScopesOrdered = <String>[
    agentActionsRunScope,
    agentActionsValidateRunScope,
    agentActionsCancelScope,
    agentActionsReadExecutionScope,
  ];

  /// `error.data.reason` when remote agent action RPCs are disabled (`enableRemoteAgentActions`).
  static const String agentActionsRemoteDisabledErrorReason = 'agent_actions_remote_disabled';

  /// `error.data.reason` when the local agent actions subsystem is disabled (`enableAgentActions`).
  static const String agentActionsFeatureDisabledErrorReason = 'agent_actions_feature_disabled';

  /// `error.data.reason` when agent action RPCs are paused (`enableAgentActionsMaintenanceMode`).
  static const String agentActionsMaintenanceModeErrorReason = 'agent_actions_maintenance_mode';

  /// `error.data.reason` when remote ad-hoc is disabled globally (`enableRemoteAdHocAgentActions`).
  static const String agentActionsRemoteAdHocDisabledErrorReason = 'agent_actions_remote_ad_hoc_disabled';

  /// `error.data.reason` when remote agent action calls exceed the configured rate limit.
  static const String agentActionRemoteRateLimitedErrorReason = 'agent_action_remote_rate_limited';

  /// `error.data.reason` when the resolved client-token policy lacks a required agent action scope.
  static const String agentActionPermissionDeniedErrorReason = 'agent_action_permission_denied';

  /// `invalid_params` / `data.reason` when a remote run or validate request omits `idempotency_key`.
  static const String remoteIdempotencyRequiredRpcReason = 'remote_idempotency_required';

  /// `invalid_params` / `data.reason` when remote run carries inline context (MVP).
  static const String remoteContextNotSupportedRpcReason = 'remote_context_not_supported';

  /// RPC param keys rejected for `agent.action.run` / `validateRun` (inline context MVP).
  static const Set<String> remoteContextRpcParamKeys = <String>{
    'context',
    'context_json',
    'context_path',
    'contextPath',
    'runtime_parameters',
    'runtimeParameters',
  };

  /// Optional RPC params for distributed tracing and hub requester identity.
  static const String agentActionRpcParamTraceId = 'trace_id';

  static const String agentActionRpcParamRequestedBy = 'requested_by';

  static const String agentActionRpcParamIdempotencyKey = 'idempotency_key';

  /// Optional remote trigger id for `agent.action.run` when multiple `remote` triggers exist.
  static const String agentActionRpcParamTriggerId = 'trigger_id';

  /// Keys omitted from RPC idempotency fingerprints (correlation-only).
  static const Set<String> agentActionRpcCorrelationOnlyParamKeys = <String>{
    agentActionRpcParamTraceId,
    agentActionRpcParamRequestedBy,
  };

  /// `invalid_params` / `data.reason` when an idempotency key is reused with a different payload fingerprint.
  static const String remoteIdempotencyFingerprintMismatchRpcReason = 'remote_idempotency_fingerprint_mismatch';

  /// JSON-RPC batch rejection reason when side-effect agent action methods are not allowed (MVP).
  static const String jsonRpcBatchMethodNotAllowedErrorReason = 'method_not_allowed_in_batch';

  /// JSON-RPC batch rejection when too many read-only `agent.action.*` methods are bundled.
  static const String jsonRpcBatchAgentActionReadLimitErrorReason = 'agent_action_batch_read_limit_exceeded';

  static const String jsonRpcBatchAgentActionReadLimitTechnicalMessagePrefix =
      'Batch contains too many read-only agent action RPC methods: ';

  /// Technical message for batch rejection: `prefix` + method name + `suffix`.
  static const String jsonRpcBatchMethodNotAllowedTechnicalMessagePrefix = 'Method ';

  static const String jsonRpcBatchMethodNotAllowedTechnicalMessageSuffix = ' is not allowed in JSON-RPC batch';

  /// `invalid_params` / `data.reason` when a remote agent action RPC that requires a response is sent as a JSON-RPC notification (no `id`).
  static const String remoteAgentActionNotificationNotAllowedRpcReason = 'notification_not_allowed';

  /// Failure `context['reason']` / RPC `error.data.reason` when cancel targets a terminal execution.
  static const String agentActionCancelAlreadyFinishedErrorReason = 'already_finished';

  /// Failure `context['reason']` / RPC `error.data.reason` when the runner could not kill the process.
  static const String agentActionCancelKillFailedErrorReason = 'kill_failed';

  /// `result['reason']` for successful `agent.action.cancel` when the runner killed the process.
  static const String agentActionCancelResultReasonKilled = 'killed';

  /// `result['reason']` for successful `agent.action.cancel` when the execution was cancelled without kill.
  static const String agentActionCancelResultReasonCancelled = 'cancelled';

  /// `result['reason']` for successful `agent.action.cancel` when cancel was recorded before terminal flags apply.
  static const String agentActionCancelResultReasonCancelRequested = 'cancel_requested';

  /// Failure `context['reason']` when an agent action entity lookup fails (`ActionNotFoundFailure`).
  static const String agentActionExecutionNotFoundContextReason = 'not_found';

  /// Failure `context['reason']` when cancel is requested but the execution is not running (and not queued).
  static const String agentActionCancelNotRunningContextReason = 'not_running';

  /// Default maximum UTF-8 bytes returned per stream when the client omits
  /// `max_output_bytes`.
  static const int defaultMaxOutputBytesPerStream = 65536;

  /// Hard cap for `max_output_bytes` requested by the client.
  static const int maxMaxOutputBytesPerStream = 524288;

  /// Resolves per-stream UTF-8 window size for `agent.action.getExecution` (schema validation may be off).
  static int resolveMaxOutputBytesPerStream(int? requested) {
    final value = requested ?? defaultMaxOutputBytesPerStream;
    if (value < 1) {
      return defaultMaxOutputBytesPerStream;
    }
    if (value > maxMaxOutputBytesPerStream) {
      return maxMaxOutputBytesPerStream;
    }
    return value;
  }

  /// Default queue caps advertised in `extensions.agentActions.defaultQueueLimits`.
  static int get remoteAgentActionsDefaultMaxConcurrent =>
      AgentActionPolicyDefaults.maxConcurrentActions;

  static int get remoteAgentActionsDefaultMaxQueued => AgentActionPolicyDefaults.maxQueuedActions;

  static int get remoteAgentActionsDefaultQueueTimeoutMs => AgentActionPolicyDefaults.defaultQueueTimeoutMs;

  /// Max inline context bytes for saved actions (remote RPC does not accept context in MVP).
  static int get remoteAgentActionsDefaultMaxContextBytes => AgentActionPolicyDefaults.maxContextBytes;

  static Map<String, Object?> get remoteAgentActionsDefaultQueueLimitsCapability =>
      AgentActionPolicyDefaults.defaultQueueLimitsCapability;

  /// Operational limits advertised in `extensions.agentActions.limits`.
  static Map<String, Object?> get remoteAgentActionsLimitsCapability =>
      AgentActionPolicyDefaults.limitsCapability(
        defaultMaxOutputBytesPerStream: defaultMaxOutputBytesPerStream,
        maxMaxOutputBytesPerStream: maxMaxOutputBytesPerStream,
      );

  /// Keys in `extensions.agentActions.batchPolicy` advertised at registration.
  static const String agentActionsBatchPolicyRunKey = 'run';

  static const String agentActionsBatchPolicyCancelKey = 'cancel';

  static const String agentActionsBatchPolicyValidateRunKey = 'validateRun';

  static const String agentActionsBatchPolicyGetExecutionKey = 'getExecution';

  /// JSON-RPC batch allowance per remote agent action method (MVP policy).
  static const Map<String, bool> remoteAgentActionsBatchPolicyCapability = <String, bool>{
    agentActionsBatchPolicyRunKey: false,
    agentActionsBatchPolicyCancelKey: false,
    agentActionsBatchPolicyValidateRunKey: true,
    agentActionsBatchPolicyGetExecutionKey: true,
  };
}
