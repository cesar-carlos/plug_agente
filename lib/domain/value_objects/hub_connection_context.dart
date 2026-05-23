/// Immutable hub connection parameters used during recovery and reconnect flows.
class HubConnectionContext {
  const HubConnectionContext({
    required this.configId,
    required this.serverUrl,
    required this.agentId,
  });

  final String configId;
  final String serverUrl;
  final String agentId;
}
