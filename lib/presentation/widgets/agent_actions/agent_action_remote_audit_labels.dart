import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

enum AgentActionRemoteAuditViewFilter { all, rpc, lifecycle }

bool isAgentActionRemoteLifecycleAuditOutcome(String outcome) {
  return outcome == AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued ||
      outcome == AgentActionRemoteAuditConstants.outcomeLifecycleStarted ||
      outcome == AgentActionRemoteAuditConstants.outcomeLifecycleCancelRequested ||
      outcome == AgentActionRemoteAuditConstants.outcomeLifecycleFinished;
}

bool matchesAgentActionRemoteAuditViewFilter(
  AgentActionRemoteAuditViewFilter filter,
  String outcome,
) {
  return switch (filter) {
    AgentActionRemoteAuditViewFilter.all => true,
    AgentActionRemoteAuditViewFilter.rpc => !isAgentActionRemoteLifecycleAuditOutcome(outcome),
    AgentActionRemoteAuditViewFilter.lifecycle => isAgentActionRemoteLifecycleAuditOutcome(outcome),
  };
}

String agentActionRemoteAuditOutcomeLabel(AppLocalizations l10n, String outcome) {
  return switch (outcome) {
    AgentActionRemoteAuditConstants.outcomeReceived => l10n.agentActionsRemoteAuditOutcomeReceived,
    AgentActionRemoteAuditConstants.outcomeSuccess => l10n.agentActionsRemoteAuditOutcomeSuccess,
    AgentActionRemoteAuditConstants.outcomeRpcError => l10n.agentActionsRemoteAuditOutcomeRpcError,
    AgentActionRemoteAuditConstants.outcomeAuthorizationDenied =>
      l10n.agentActionsRemoteAuditOutcomeAuthorizationDenied,
    AgentActionRemoteAuditConstants.outcomeNotificationRejected =>
      l10n.agentActionsRemoteAuditOutcomeNotificationRejected,
    AgentActionRemoteAuditConstants.outcomeRateLimited => l10n.agentActionsRemoteAuditOutcomeRateLimited,
    AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued => l10n.agentActionsRemoteAuditOutcomeLifecycleEnqueued,
    AgentActionRemoteAuditConstants.outcomeLifecycleStarted => l10n.agentActionsRemoteAuditOutcomeLifecycleStarted,
    AgentActionRemoteAuditConstants.outcomeLifecycleCancelRequested =>
      l10n.agentActionsRemoteAuditOutcomeLifecycleCancelRequested,
    AgentActionRemoteAuditConstants.outcomeLifecycleFinished => l10n.agentActionsRemoteAuditOutcomeLifecycleFinished,
    _ => outcome,
  };
}

String agentActionRemoteAuditReasonCodeLabel(AppLocalizations l10n, String reasonCode) {
  final statusLabel = _executionStatusLabelFromReasonCode(l10n, reasonCode);
  if (statusLabel != null) {
    return statusLabel;
  }

  return switch (reasonCode) {
    RpcClientTokenConstants.missingClientTokenReason => l10n.agentActionsRemoteAuditReasonMissingClientToken,
    AgentActionRpcConstants.agentActionPermissionDeniedErrorReason =>
      l10n.agentActionsRemoteAuditReasonPermissionDenied,
    AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason =>
      l10n.agentActionsRemoteAuditReasonRemoteRateLimited,
    AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason => l10n.agentActionsRemoteAuditReasonRemoteDisabled,
    AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason => l10n.agentActionsRemoteAuditReasonFeatureDisabled,
    AgentActionRpcConstants.agentActionsMaintenanceModeErrorReason => l10n.agentActionsRemoteAuditReasonMaintenanceMode,
    AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason =>
      l10n.agentActionsRemoteAuditReasonNotificationNotAllowed,
    AgentActionRpcConstants.remoteContextNotSupportedRpcReason =>
      l10n.agentActionsRemoteAuditReasonRemoteContextNotSupported,
    AgentActionRpcConstants.remoteIdempotencyRequiredRpcReason => l10n.agentActionsRemoteAuditReasonIdempotencyRequired,
    AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason =>
      l10n.agentActionsRemoteAuditReasonIdempotencyMismatch,
    AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedErrorReason =>
      l10n.agentActionsRemoteAuditReasonBatchNotAllowed,
    'execution_not_found' => l10n.agentActionsRemoteAuditReasonExecutionNotFound,
    AgentActionRpcConstants.agentActionCancelAlreadyFinishedErrorReason =>
      l10n.agentActionsRemoteAuditReasonAlreadyFinished,
    AgentActionRpcConstants.agentActionCancelKillFailedErrorReason => l10n.agentActionsRemoteAuditReasonKillFailed,
    _ => reasonCode,
  };
}

String? _executionStatusLabelFromReasonCode(AppLocalizations l10n, String reasonCode) {
  return switch (reasonCode) {
    'queued' => l10n.agentActionsStatusQueued,
    'running' => l10n.agentActionsStatusRunning,
    'succeeded' => l10n.agentActionsStatusSucceeded,
    'failed' => l10n.agentActionsStatusFailed,
    'skipped' => l10n.agentActionsStatusSkipped,
    'cancelled' => l10n.agentActionsStatusCancelled,
    'killed' => l10n.agentActionsStatusKilled,
    'timedOut' => l10n.agentActionsStatusTimedOut,
    'interrupted' => l10n.agentActionsStatusInterrupted,
    'unknown' => l10n.agentActionsStatusUnknown,
    _ => null,
  };
}

String formatAgentActionRemoteAuditSubtitle(
  AppLocalizations l10n,
  AgentActionRemoteAuditRecord record,
) {
  final parts = <String>[
    if (record.actionId != null && record.actionId!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldAction}: ${record.actionId!.trim()}',
    if (record.executionId != null && record.executionId!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldExecution}: ${record.executionId!.trim()}',
    if (record.traceId != null && record.traceId!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldTrace}: ${record.traceId!.trim()}',
    if (record.requestedBy != null && record.requestedBy!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldRequestedBy}: ${record.requestedBy!.trim()}',
    if (record.idempotencyKey != null && record.idempotencyKey!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldIdempotencyKey}: ${record.idempotencyKey!.trim()}',
    if (record.reasonCode != null && record.reasonCode!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldReason}: ${agentActionRemoteAuditReasonCodeLabel(l10n, record.reasonCode!.trim())}',
    if (record.clientId != null && record.clientId!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldClient}: ${record.clientId!.trim()}',
    if (record.runtimeInstanceId != null && record.runtimeInstanceId!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldRuntimeInstance}: ${record.runtimeInstanceId!.trim()}',
    if (record.runtimeSessionId != null && record.runtimeSessionId!.trim().isNotEmpty)
      '${l10n.agentActionsRemoteAuditFieldRuntimeSession}: ${record.runtimeSessionId!.trim()}',
  ];
  return parts.join(' · ');
}
