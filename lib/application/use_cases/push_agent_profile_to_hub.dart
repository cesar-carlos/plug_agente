import 'package:plug_agente/application/mappers/agent_profile_hub_patch_mapper.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class PushAgentProfileToHub {
  PushAgentProfileToHub(
    this._gateway,
    this._uuid,
  );

  final IAgentHubProfileGateway _gateway;
  final Uuid _uuid;

  Future<Result<AgentHubProfilePushResult>> call({
    required String serverUrl,
    required String agentId,
    required String accessToken,
    required AgentProfile profile,
    int? expectedProfileVersion,
  }) {
    final idempotencyKey = _uuid.v4();
    final body = agentProfileToHubPatchBody(
      profile,
      expectedProfileVersion: expectedProfileVersion,
      idempotencyKey: idempotencyKey,
    );

    return _gateway.patchProfile(
      serverUrl: serverUrl,
      agentId: agentId,
      accessToken: accessToken,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }
}
