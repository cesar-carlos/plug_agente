import 'package:plug_agente/domain/actions/actions.dart';

/// Pure assembly helpers for turning editor input into domain policy/value
/// objects when saving an [AgentActionDefinition].
///
/// Extracted from `AgentActionsProvider` so the policy-merge and
/// path-reference rules can be unit-tested without the provider's state and
/// side effects. Stateless: safe to use as a `const` collaborator.
class AgentActionDefinitionAssembler {
  const AgentActionDefinitionAssembler();

  AgentActionPathReference pathReference(
    String originalPath, {
    AgentActionPathChangePolicy? pathChangePolicy,
  }) {
    return AgentActionPathReference(
      originalPath: originalPath,
      pathChangePolicy: pathChangePolicy,
    );
  }

  AgentActionPathReference? optionalPathReference(
    String? originalPath, {
    AgentActionPathChangePolicy? pathChangePolicy,
  }) {
    final trimmed = originalPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return pathReference(trimmed, pathChangePolicy: pathChangePolicy);
  }

  /// Merges the supplied policies onto the [existing] definition's policies,
  /// preserving previously persisted encoding/capture/queue/path policies when
  /// the caller does not override them.
  AgentActionDefinitionPolicies policiesForSave({
    required AgentActionDefinition? existing,
    required AgentActionNotificationPolicy notificationPolicy,
    required AgentActionRetryPolicy retryPolicy,
    required AgentActionTimeoutPolicy timeoutPolicy,
    required AgentActionEnvironmentPolicy environmentPolicy,
    required AgentActionExitCodePolicy exitCodePolicy,
    required AgentActionProcessPolicy processPolicy,
    required AgentActionLifecyclePolicy lifecyclePolicy,
    required AgentActionRemotePolicy remotePolicy,
    required AgentActionElevatedPolicy elevatedPolicy,
    AgentActionContextPolicy? contextPolicy,
    AgentActionEncodingPolicy? encodingPolicy,
    AgentActionCapturePolicy? capturePolicy,
    AgentActionQueuePolicy? queuePolicy,
    AgentActionPathPolicy? pathPolicy,
  }) {
    return (existing?.policies ?? const AgentActionDefinitionPolicies()).copyWith(
      notification: notificationPolicy,
      retry: retryPolicy,
      timeout: timeoutPolicy,
      environment: environmentPolicy,
      exitCode: exitCodePolicy,
      process: processPolicy,
      lifecycle: lifecyclePolicy,
      remote: remotePolicy,
      elevated: elevatedPolicy,
      context: contextPolicy,
      encoding: encodingPolicy ?? existing?.policies.encoding,
      capture: capturePolicy ?? existing?.policies.capture,
      queue: queuePolicy ?? existing?.policies.queue,
      path: pathPolicy ?? existing?.policies.path,
    );
  }
}
