import 'package:plug_agente/application/validation/agent_profile_schema.dart';

/// Builds the JSON body for `PATCH /api/v1/agents/{agentId}/profile` (camelCase).
///
/// Optional fields use JSON `null` when absent on [AgentProfile] so the hub clears
/// stored values instead of leaving them unchanged (omit vs null semantics).
Map<String, dynamic> agentProfileToHubPatchBody(
  AgentProfile profile, {
  int? expectedProfileVersion,
  String? idempotencyKey,
}) {
  final body = <String, dynamic>{
    'name': profile.name,
    'tradeName': profile.tradeName,
    'document': profile.document,
    'documentType': profile.documentType,
    'phone': profile.phone,
    'mobile': profile.mobile,
    'email': profile.email,
    'address': <String, dynamic>{
      'street': profile.address.street,
      'number': profile.address.number,
      'district': profile.address.district,
      'postalCode': profile.address.postalCode,
      'city': profile.address.city,
      'state': profile.address.state,
    },
    'notes': profile.notes,
  };
  if (expectedProfileVersion != null) {
    body['expectedProfileVersion'] = expectedProfileVersion;
  }
  if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
    body['idempotencyKey'] = idempotencyKey;
  }
  return body;
}
