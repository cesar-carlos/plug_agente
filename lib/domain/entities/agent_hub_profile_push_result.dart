/// Result of a successful hub agent profile PATCH.
class AgentHubProfilePushResult {
  const AgentHubProfilePushResult({
    required this.profileVersion,
    this.profileUpdatedAt,
  });

  final int profileVersion;
  final String? profileUpdatedAt;
}
