import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_remote_audit_labels.dart';

AppLocalizations _enL10n() => lookupAppLocalizations(const Locale('en'));

void main() {
  test('should classify lifecycle audit outcomes', () {
    check(isAgentActionRemoteLifecycleAuditOutcome(AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued))
        .isTrue();
    check(isAgentActionRemoteLifecycleAuditOutcome(AgentActionRemoteAuditConstants.outcomeLifecycleFinished))
        .isTrue();
    check(isAgentActionRemoteLifecycleAuditOutcome(AgentActionRemoteAuditConstants.outcomeSuccess)).isFalse();
    check(isAgentActionRemoteLifecycleAuditOutcome(AgentActionRemoteAuditConstants.outcomeReceived)).isFalse();
  });

  test('should filter rows by view filter', () {
    check(
      matchesAgentActionRemoteAuditViewFilter(
        AgentActionRemoteAuditViewFilter.lifecycle,
        AgentActionRemoteAuditConstants.outcomeLifecycleStarted,
      ),
    ).isTrue();
    check(
      matchesAgentActionRemoteAuditViewFilter(
        AgentActionRemoteAuditViewFilter.rpc,
        AgentActionRemoteAuditConstants.outcomeLifecycleStarted,
      ),
    ).isFalse();
    check(
      matchesAgentActionRemoteAuditViewFilter(
        AgentActionRemoteAuditViewFilter.rpc,
        AgentActionRemoteAuditConstants.outcomeSuccess,
      ),
    ).isTrue();
    check(
      matchesAgentActionRemoteAuditViewFilter(
        AgentActionRemoteAuditViewFilter.all,
        AgentActionRemoteAuditConstants.outcomeRateLimited,
      ),
    ).isTrue();
  });

  test('should localize common remote audit reason codes', () {
    final l10n = _enL10n();
    check(agentActionRemoteAuditReasonCodeLabel(l10n, RpcClientTokenConstants.missingClientTokenReason))
        .equals(l10n.agentActionsRemoteAuditReasonMissingClientToken);
    check(
      agentActionRemoteAuditReasonCodeLabel(
        l10n,
        AgentActionRpcConstants.agentActionPermissionDeniedErrorReason,
      ),
    ).equals(l10n.agentActionsRemoteAuditReasonPermissionDenied);
    check(agentActionRemoteAuditReasonCodeLabel(l10n, 'succeeded')).equals(l10n.agentActionsStatusSucceeded);
    check(agentActionRemoteAuditReasonCodeLabel(l10n, 'custom_unknown_reason')).equals('custom_unknown_reason');
  });

  test('should format audit subtitle with localized field labels and reason', () {
    final l10n = _enL10n();
    final subtitle = formatAgentActionRemoteAuditSubtitle(
      l10n,
      AgentActionRemoteAuditRecord(
        id: 'a1',
        occurredAtUtc: DateTime.utc(2026, 5, 18),
        rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
        outcome: AgentActionRemoteAuditConstants.outcomeAuthorizationDenied,
        credentialPresent: false,
        actionId: 'action-1',
        traceId: 'trace-1',
        requestedBy: 'hub',
        reasonCode: RpcClientTokenConstants.missingClientTokenReason,
        idempotencyKey: 'idem-audit-1',
        clientId: 'client-1',
      ),
    );
    check(subtitle.contains('${l10n.agentActionsRemoteAuditFieldAction}: action-1')).isTrue();
    check(subtitle.contains('${l10n.agentActionsRemoteAuditFieldIdempotencyKey}: idem-audit-1')).isTrue();
    check(subtitle.contains('${l10n.agentActionsRemoteAuditFieldTrace}: trace-1')).isTrue();
    check(subtitle.contains(l10n.agentActionsRemoteAuditReasonMissingClientToken)).isTrue();
    check(subtitle.contains('${l10n.agentActionsRemoteAuditFieldClient}: client-1')).isTrue();
  });
}
