import 'package:plug_agente/application/validation/agent_profile_schema.dart';

class FetchedAgentHubProfile {
  const FetchedAgentHubProfile({
    required this.profile,
    required this.profileVersion,
    this.profileUpdatedAt,
  });

  final AgentProfile profile;
  final int profileVersion;
  final String? profileUpdatedAt;
}
