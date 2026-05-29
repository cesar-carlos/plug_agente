/// Hub catalog row returned by `GET /api/v1/agents/{agentId}/profile`.
///
/// [agentPayload] keeps the hub `agent` object (camelCase) for application-layer
/// mapping into the validated profile model.
class AgentHubProfileCatalogSnapshot {
  const AgentHubProfileCatalogSnapshot({
    required this.profileVersion,
    required this.agentPayload,
    this.profileUpdatedAt,
  });

  final int profileVersion;
  final String? profileUpdatedAt;
  final Map<String, dynamic> agentPayload;
}
