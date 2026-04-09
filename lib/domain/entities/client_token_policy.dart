import 'package:plug_agente/core/utils/sensitive_map_redactor.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

class ClientTokenPolicy {
  const ClientTokenPolicy({
    required this.clientId,
    required this.allTables,
    required this.allViews,
    required this.allPermissions,
    required this.rules,
    this.agentId,
    this.payload = const <String, dynamic>{},
    this.isRevoked = false,
    this.tokenId,
    this.issuedAt,
    this.tokenUpdatedAt,
  });

  factory ClientTokenPolicy.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'] as List<dynamic>? ?? const <dynamic>[];
    final parsedRules = rawRules.whereType<Map<String, dynamic>>().map(ClientTokenRule.fromJson).toList();

    return ClientTokenPolicy(
      clientId: json['client_id'] as String? ?? '',
      agentId: json['agent_id'] as String?,
      payload: json['payload'] as Map<String, dynamic>? ?? const {},
      allTables: json['all_tables'] as bool? ?? false,
      allViews: json['all_views'] as bool? ?? false,
      allPermissions: json['all_permissions'] as bool? ?? false,
      isRevoked: json['is_revoked'] as bool? ?? false,
      rules: parsedRules,
      tokenId: json['token_id'] as String?,
      issuedAt: _parseDateTimeOrNull(json['issued_at']),
      tokenUpdatedAt: _parseDateTimeOrNull(json['updated_at']),
    );
  }

  final String clientId;
  final String? agentId;
  final Map<String, dynamic> payload;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final List<ClientTokenRule> rules;
  final bool isRevoked;
  final String? tokenId;
  final DateTime? issuedAt;
  final DateTime? tokenUpdatedAt;

  bool isAllowed({
    required SqlOperation operation,
    required DatabaseResource resource,
  }) {
    if (isRevoked) {
      return false;
    }

    var hasExplicitAllow = false;
    for (final rule in rules) {
      if (!rule.appliesTo(resource)) {
        continue;
      }
      if (rule.effect == ClientTokenRuleEffect.deny && rule.affectsOperation(operation)) {
        return false;
      }
      if (rule.effect == ClientTokenRuleEffect.allow && rule.affectsOperation(operation)) {
        hasExplicitAllow = true;
      }
    }

    if (hasExplicitAllow) {
      return true;
    }

    if (allPermissions) {
      return true;
    }

    final supportsResource = switch (resource.resourceType) {
      DatabaseResourceType.table => allTables,
      DatabaseResourceType.view => allViews,
      DatabaseResourceType.unknown => allTables || allViews,
    };

    return supportsResource;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'client_id': clientId,
      if (agentId != null) 'agent_id': agentId,
      'payload': payload,
      'all_tables': allTables,
      'all_views': allViews,
      'all_permissions': allPermissions,
      'is_revoked': isRevoked,
      'rules': rules.map((rule) => rule.toJson()).toList(),
      if (tokenId != null) 'token_id': tokenId,
      if (issuedAt != null) 'issued_at': issuedAt!.toUtc().toIso8601String(),
      if (tokenUpdatedAt != null) 'updated_at': tokenUpdatedAt!.toUtc().toIso8601String(),
    };
  }

  /// RPC result map for client_token.getPolicy: metadata plus payload redacted for common secret-like keys.
  Map<String, dynamic> toRpcResultJson() {
    return <String, dynamic>{
      'client_id': clientId,
      if (agentId != null) 'agent_id': agentId,
      'payload': SensitiveMapRedactor.redactForRpc(payload),
      'all_tables': allTables,
      'all_views': allViews,
      'all_permissions': allPermissions,
      'is_revoked': isRevoked,
      'rules': rules.map((rule) => rule.toJson()).toList(),
      if (tokenId != null) 'token_id': tokenId,
      if (issuedAt != null) 'issued_at': issuedAt!.toUtc().toIso8601String(),
      if (tokenUpdatedAt != null) 'updated_at': tokenUpdatedAt!.toUtc().toIso8601String(),
    };
  }

  static DateTime? _parseDateTimeOrNull(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
