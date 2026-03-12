import 'package:plug_agente/domain/entities/client_token_rule.dart';

class ClientTokenCreateRequest {
  const ClientTokenCreateRequest({
    required this.clientId,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.rules,
    this.payload = const <String, dynamic>{},
    this.agentId,
  });

  final String clientId;
  final String? agentId;
  final Map<String, dynamic> payload;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final List<ClientTokenRule> rules;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'client_id': clientId,
      if (agentId != null) 'agent_id': agentId,
      'payload': payload,
      'all_tables': allTables,
      'all_views': allViews,
      'all_permissions': allPermissions,
      'rules': rules.map((rule) => rule.toJson()).toList(),
    };
  }
}
