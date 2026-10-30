final class ActionIoSessionReference {
  const ActionIoSessionReference({
    required this.executionId,
    required this.installationId,
    required this.agentId,
    required this.clientId,
    required this.actionId,
    this.triggerId = '',
    this.definitionHash = '',
    this.actionType,
  });
  final String executionId;
  final String installationId;
  final String agentId;
  final String clientId;
  final String actionId;
  final String triggerId;
  final String definitionHash;
  final String? actionType;
}

final class ActionIoExecutionLookup {
  const ActionIoExecutionLookup(this.session);
  final ActionIoSessionReference? session;
}
