import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_catalog_snapshot.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Maps hub `agent` catalog JSON (camelCase) into a validated [AgentProfile].
Result<AgentProfile> agentProfileFromHubCatalogSnapshot(
  AgentHubProfileCatalogSnapshot snapshot, {
  AgentProfileValidationMessages? validationMessages,
}) {
  return agentProfileFromHubAgentPayload(
    snapshot.agentPayload,
    validationMessages: validationMessages,
  );
}

Result<AgentProfile> agentProfileFromHubAgentPayload(
  Map<String, dynamic> agent, {
  AgentProfileValidationMessages? validationMessages,
}) {
  final address = _readJsonMap(agent['address']);
  if (address == null) {
    return Failure(
      domain.ServerFailure.withContext(
        message: 'Hub profile is missing address',
        context: const {'operation': 'parseHubAgentProfile'},
      ),
    );
  }

  final payload = <String, dynamic>{
    'name': agent['name'],
    'trade_name': agent['tradeName'] ?? agent['trade_name'],
    'document': agent['document'],
    'document_type': agent['documentType'] ?? agent['document_type'],
    if (agent['phone'] != null) 'phone': agent['phone'],
    'mobile': agent['mobile'],
    'email': agent['email'],
    'address': <String, dynamic>{
      'street': address['street'],
      'number': address['number'],
      'district': address['district'],
      'postal_code': address['postalCode'] ?? address['postal_code'],
      'city': address['city'],
      'state': address['state'],
    },
    if (agent['notes'] != null) 'notes': agent['notes'],
  };

  return AgentProfile.fromRpcPayload(
    payload,
    validationMessages:
        validationMessages ?? AgentProfileValidationMessages.english,
  );
}

Map<String, dynamic>? _readJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}
