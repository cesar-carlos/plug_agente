import 'package:plug_agente/application/dtos/fetched_agent_hub_profile.dart';
import 'package:plug_agente/application/mappers/agent_profile_hub_response_mapper.dart';
import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// Loads the agent catalog profile from the hub HTTP API.
class FetchAgentHubProfile {
  FetchAgentHubProfile(this._gateway);

  final IAgentHubProfileGateway _gateway;

  Future<Result<FetchedAgentHubProfile>> call({
    required String serverUrl,
    required String agentId,
    required String accessToken,
    String? configId,
    AgentProfileValidationMessages? validationMessages,
  }) async {
    final catalogResult = await _gateway.fetchProfileCatalog(
      serverUrl: serverUrl,
      agentId: agentId,
      accessToken: accessToken,
      configId: configId,
    );

    if (catalogResult.isError()) {
      return Failure(catalogResult.exceptionOrNull()!);
    }

    final catalog = catalogResult.getOrThrow();
    final profileResult = agentProfileFromHubCatalogSnapshot(
      catalog,
      validationMessages: validationMessages,
    );

    if (profileResult.isError()) {
      return Failure(profileResult.exceptionOrNull()!);
    }

    return Success(
      FetchedAgentHubProfile(
        profile: profileResult.getOrThrow(),
        profileVersion: catalog.profileVersion,
        profileUpdatedAt: catalog.profileUpdatedAt,
      ),
    );
  }
}
