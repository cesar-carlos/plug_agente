import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/domain/actions/actions.dart';

/// Reconciles [AgentActionRemotePolicy] on save when risk-bearing fields change.
class AgentActionRemoteApprovalReconciler {
  const AgentActionRemoteApprovalReconciler(
    this._snapshotter, {
    AgentActionSecretReferenceFingerprinter? secretFingerprinter,
  }) : _secretFingerprinter = secretFingerprinter;

  final AgentActionDefinitionSnapshotter _snapshotter;
  final AgentActionSecretReferenceFingerprinter? _secretFingerprinter;

  Future<AgentActionRemotePolicy> reconcileAsync({
    required AgentActionRemotePolicy incoming,
    required AgentActionRemotePolicy? previous,
    required AgentActionDefinition definition,
  }) async {
    if (!incoming.isEnabled) {
      return const AgentActionRemotePolicy();
    }

    final secretFingerprints = await _resolveSecretFingerprints(definition);
    final newFingerprint = _snapshotter.riskFingerprint(
      definition,
      secretReferenceFingerprints: secretFingerprints,
    );
    final previousApprovedAt = previous?.approvedAt;

    final explicitlyReApproved =
        incoming.approvedAt != null &&
        !incoming.requiresReapproval &&
        (previousApprovedAt == null || incoming.approvedAt!.isAfter(previousApprovedAt));

    if (explicitlyReApproved) {
      return incoming.copyWith(riskFingerprint: newFingerprint);
    }

    final hadApproval = previousApprovedAt != null;
    final approvedFingerprint = previous?.riskFingerprint;

    if (hadApproval && approvedFingerprint != null && approvedFingerprint != newFingerprint) {
      return incoming.copyWith(
        requiresReapproval: true,
        riskFingerprint: approvedFingerprint,
        approvedAt: previousApprovedAt,
        approvedBy: previous?.approvedBy,
        approvalReason: previous?.approvalReason,
      );
    }

    if (incoming.requiresReapproval) {
      return incoming.copyWith(
        riskFingerprint: approvedFingerprint ?? newFingerprint,
      );
    }

    return incoming.copyWith(riskFingerprint: newFingerprint);
  }

  /// Synchronous reconcile without secret-store fingerprints (tests / no store).
  AgentActionRemotePolicy reconcile({
    required AgentActionRemotePolicy incoming,
    required AgentActionRemotePolicy? previous,
    required AgentActionDefinition definition,
  }) {
    if (!incoming.isEnabled) {
      return const AgentActionRemotePolicy();
    }

    final newFingerprint = _snapshotter.riskFingerprint(definition);
    final previousApprovedAt = previous?.approvedAt;

    final explicitlyReApproved =
        incoming.approvedAt != null &&
        !incoming.requiresReapproval &&
        (previousApprovedAt == null || incoming.approvedAt!.isAfter(previousApprovedAt));

    if (explicitlyReApproved) {
      return incoming.copyWith(riskFingerprint: newFingerprint);
    }

    final hadApproval = previousApprovedAt != null;
    final approvedFingerprint = previous?.riskFingerprint;

    if (hadApproval && approvedFingerprint != null && approvedFingerprint != newFingerprint) {
      return incoming.copyWith(
        requiresReapproval: true,
        riskFingerprint: approvedFingerprint,
        approvedAt: previousApprovedAt,
        approvedBy: previous?.approvedBy,
        approvalReason: previous?.approvalReason,
      );
    }

    if (incoming.requiresReapproval) {
      return incoming.copyWith(
        riskFingerprint: approvedFingerprint ?? newFingerprint,
      );
    }

    return incoming.copyWith(riskFingerprint: newFingerprint);
  }

  Future<Map<String, String>?> _resolveSecretFingerprints(AgentActionDefinition definition) async {
    final fingerprinter = _secretFingerprinter;
    if (fingerprinter == null) {
      return null;
    }
    final fingerprints = await fingerprinter.fingerprintsFor(definition);
    return fingerprints.isEmpty ? null : fingerprints;
  }
}
