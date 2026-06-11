import 'package:plug_agente/domain/actions/actions.dart';

/// Shared definition metadata and policies for agent action save operations.
final class AgentActionDefinitionSaveOptions {
  const AgentActionDefinitionSaveOptions({
    this.state = AgentActionState.needsValidation,
    this.notificationPolicy = const AgentActionNotificationPolicy(),
    this.retryPolicy = const AgentActionRetryPolicy(),
    this.timeoutPolicy = const AgentActionTimeoutPolicy(),
    this.environmentPolicy = const AgentActionEnvironmentPolicy(),
    this.exitCodePolicy = const AgentActionExitCodePolicy(),
    this.processPolicy = const AgentActionProcessPolicy(),
    this.lifecyclePolicy = const AgentActionLifecyclePolicy(),
    this.remotePolicy = const AgentActionRemotePolicy(),
    this.elevatedPolicy = const AgentActionElevatedPolicy(),
    this.contextPolicy,
    this.pathChangePolicy,
    this.encodingPolicy = const AgentActionEncodingPolicy(),
    this.capturePolicy = const AgentActionCapturePolicy(),
    this.queuePolicy = const AgentActionQueuePolicy(),
    this.pathPolicy = const AgentActionPathPolicy(),
  });

  final AgentActionState state;
  final AgentActionNotificationPolicy notificationPolicy;
  final AgentActionRetryPolicy retryPolicy;
  final AgentActionTimeoutPolicy timeoutPolicy;
  final AgentActionEnvironmentPolicy environmentPolicy;
  final AgentActionExitCodePolicy exitCodePolicy;
  final AgentActionProcessPolicy processPolicy;
  final AgentActionLifecyclePolicy lifecyclePolicy;
  final AgentActionRemotePolicy remotePolicy;
  final AgentActionElevatedPolicy elevatedPolicy;
  final AgentActionContextPolicy? contextPolicy;
  final AgentActionPathChangePolicy? pathChangePolicy;
  final AgentActionEncodingPolicy encodingPolicy;
  final AgentActionCapturePolicy capturePolicy;
  final AgentActionQueuePolicy queuePolicy;
  final AgentActionPathPolicy pathPolicy;
}

typedef AgentActionDefinitionSaveDelegate =
    Future<bool> Function(
      AgentActionDefinitionSaveOptions options,
    );

AgentActionDefinitionSaveOptions buildAgentActionDefinitionSaveOptions({
  AgentActionState state = AgentActionState.needsValidation,
  AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
  AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
  AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
  AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
  AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
  AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
  AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
  AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
  AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
  AgentActionContextPolicy? contextPolicy,
  AgentActionPathChangePolicy? pathChangePolicy,
  AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
  AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
  AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
  AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
}) {
  return AgentActionDefinitionSaveOptions(
    state: state,
    notificationPolicy: notificationPolicy,
    retryPolicy: retryPolicy,
    timeoutPolicy: timeoutPolicy,
    environmentPolicy: environmentPolicy,
    exitCodePolicy: exitCodePolicy,
    processPolicy: processPolicy,
    lifecyclePolicy: lifecyclePolicy,
    remotePolicy: remotePolicy,
    elevatedPolicy: elevatedPolicy,
    contextPolicy: contextPolicy,
    pathChangePolicy: pathChangePolicy,
    encodingPolicy: encodingPolicy,
    capturePolicy: capturePolicy,
    queuePolicy: queuePolicy,
    pathPolicy: pathPolicy,
  );
}
