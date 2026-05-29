import 'package:plug_agente/domain/entities/agent_hub_profile_catalog_snapshot.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:result_dart/result_dart.dart';

/// Remote gateway for the authenticated agent catalog profile on the hub (HTTP).
///
/// PATCH/GET ` /api/v1/agents/{agentId}/profile`. The `body` map must match the hub
/// HTTP schema (camelCase); build it in the application layer.
abstract class IAgentHubProfileGateway {
  Future<Result<AgentHubProfilePushResult>> patchProfile({
    required String serverUrl,
    required String agentId,
    required String accessToken,
    required Map<String, dynamic> body,
    String? idempotencyKey,
  });

  Future<Result<AgentHubProfileCatalogSnapshot>> fetchProfileCatalog({
    required String serverUrl,
    required String agentId,
    required String accessToken,
  });
}
