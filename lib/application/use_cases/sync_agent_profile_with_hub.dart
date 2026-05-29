import 'package:plug_agente/application/dtos/agent_profile_hub_sync_result.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart';
/// Pushes the validated profile to the hub when the session is eligible for HTTP catalog sync.
///
/// On login/connection the same catalog is also sent via Socket.IO `agent.register`
/// snapshot; this use case covers the authenticated REST PATCH after manual save.
class SyncAgentProfileWithHub {
  SyncAgentProfileWithHub(this._pushAgentProfileToHub);

  final PushAgentProfileToHub _pushAgentProfileToHub;

  Future<AgentProfileHubSyncResult> call({
    required AgentProfile profile,
    required String serverUrl,
    required String agentId,
    required String accessToken,
    required bool isHubConnected,
    int? expectedProfileVersion,
  }) async {
    if (!isHubConnected) {
      return const AgentProfileHubSyncSkipped(AgentProfileHubSyncSkipReason.hubNotConnected);
    }

    if (accessToken.trim().isEmpty ||
        serverUrl.trim().isEmpty ||
        agentId.trim().isEmpty) {
      return const AgentProfileHubSyncSkipped(
        AgentProfileHubSyncSkipReason.missingCredentials,
      );
    }

    final pushResult = await _pushAgentProfileToHub(
      serverUrl: serverUrl,
      agentId: agentId,
      accessToken: accessToken,
      profile: profile,
      expectedProfileVersion: expectedProfileVersion,
    );

    if (pushResult.isError()) {
      return AgentProfileHubSyncPushFailed(_asFailure(pushResult.exceptionOrNull()!));
    }

    final synced = pushResult.getOrThrow();
    return AgentProfileHubSyncSucceeded(
      profileVersion: synced.profileVersion,
      profileUpdatedAt: synced.profileUpdatedAt,
    );
  }

  Failure _asFailure(Object error) {
    if (error is Failure) {
      return error;
    }
    return ServerFailure(error.toString());
  }
}
