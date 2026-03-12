import 'package:plug_agente/domain/entities/client_token_rule.dart';

class ClientTokenSummary {
  const ClientTokenSummary({
    required this.id,
    required this.clientId,
    required this.createdAt,
    required this.isRevoked,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.rules,
    this.agentId,
    this.payload = const <String, dynamic>{},
  });

  factory ClientTokenSummary.fromJson(Map<String, dynamic> json) {
    final policyJson = json['policy'] as Map<String, dynamic>?;
    final source = policyJson ?? json;
    final rawRules = source['rules'] as List<dynamic>? ?? const <dynamic>[];
    final parsedRules = rawRules.whereType<Map<String, dynamic>>().map(ClientTokenRule.fromJson).toList();

    return ClientTokenSummary(
      id: json['id'] as String? ?? '',
      clientId: source['client_id'] as String? ?? json['client_id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(
            json['created_at'] as String? ?? '',
          ) ??
          DateTime.now(),
      isRevoked: source['is_revoked'] as bool? ?? json['is_revoked'] as bool? ?? false,
      agentId: source['agent_id'] as String?,
      payload: source['payload'] as Map<String, dynamic>? ?? const {},
      allTables: source['all_tables'] as bool? ?? false,
      allViews: source['all_views'] as bool? ?? false,
      allPermissions: source['all_permissions'] as bool? ?? false,
      rules: parsedRules,
    );
  }

  final String id;
  final String clientId;
  final DateTime createdAt;
  final bool isRevoked;
  final String? agentId;
  final Map<String, dynamic> payload;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final List<ClientTokenRule> rules;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'client_id': clientId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_revoked': isRevoked,
      if (agentId != null) 'agent_id': agentId,
      'payload': payload,
      'all_tables': allTables,
      'all_views': allViews,
      'all_permissions': allPermissions,
      'rules': rules.map((rule) => rule.toJson()).toList(),
    };
  }
}
