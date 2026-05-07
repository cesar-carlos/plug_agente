import 'package:plug_agente/core/utils/sensitive_map_redactor.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

class ClientTokenPolicy {
  const ClientTokenPolicy({
    required this.clientId,
    required bool allTables,
    required bool allViews,
    required this.rules,
    ClientPermissionSet? globalPermissions,
    bool? allPermissions,
    this.agentId,
    this.payload = const <String, dynamic>{},
    this.isRevoked = false,
    this.tokenId,
    this.issuedAt,
    this.tokenUpdatedAt,
  }) : allTables = allTables || (allPermissions ?? false),
       allViews = allViews || (allPermissions ?? false),
       globalPermissions =
           globalPermissions ??
           ((allPermissions ?? false)
               ? ClientPermissionSet.fullAccess
               : ((allTables || allViews) ? ClientPermissionSet.legacyScopedAccess : ClientPermissionSet.none));

  factory ClientTokenPolicy.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'] as List<dynamic>? ?? const <dynamic>[];
    final parsedRules = rawRules.whereType<Map<String, dynamic>>().map(ClientTokenRule.fromJson).toList();
    final legacyAllPermissions = json['all_permissions'] as bool? ?? false;

    return ClientTokenPolicy(
      clientId: json['client_id'] as String? ?? '',
      agentId: json['agent_id'] as String?,
      payload: _parsePayload(json['payload']),
      allTables: json['all_tables'] as bool? ?? legacyAllPermissions,
      allViews: json['all_views'] as bool? ?? legacyAllPermissions,
      globalPermissions: _parseGlobalPermissions(json),
      allPermissions: legacyAllPermissions,
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
  final ClientPermissionSet globalPermissions;
  final List<ClientTokenRule> rules;
  final bool isRevoked;
  final String? tokenId;
  final DateTime? issuedAt;
  final DateTime? tokenUpdatedAt;

  bool get allPermissions => allTables && allViews && globalPermissions.isFullAccess;

  String? get payloadDatabaseConstraint => _normalizeDatabaseName(payload['database']);

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

    final supportsResource = switch (resource.resourceType) {
      DatabaseResourceType.table => allTables && globalPermissions.allows(operation),
      DatabaseResourceType.view => allViews && globalPermissions.allows(operation),
      DatabaseResourceType.unknown => (allTables || allViews) && globalPermissions.allows(operation),
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
      'global_permissions': globalPermissions.toJson(),
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
      'global_permissions': globalPermissions.toJson(),
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

  static Map<String, dynamic> _parsePayload(Object? rawValue) {
    if (rawValue is Map<dynamic, dynamic>) {
      return Map<String, dynamic>.from(rawValue);
    }
    return const <String, dynamic>{};
  }

  static ClientPermissionSet _parseGlobalPermissions(
    Map<String, dynamic> source,
  ) {
    final rawGlobalPermissions = source['global_permissions'];
    if (rawGlobalPermissions is Map<dynamic, dynamic>) {
      return ClientPermissionSet.fromJson(
        Map<String, dynamic>.from(rawGlobalPermissions),
      );
    }

    final legacyAllPermissions = source['all_permissions'] as bool? ?? false;
    if (legacyAllPermissions) {
      return ClientPermissionSet.fullAccess;
    }

    final legacyAllTables = source['all_tables'] as bool? ?? false;
    final legacyAllViews = source['all_views'] as bool? ?? false;
    if (legacyAllTables || legacyAllViews) {
      return ClientPermissionSet.legacyScopedAccess;
    }

    return ClientPermissionSet.none;
  }

  static String? _normalizeDatabaseName(Object? rawValue) {
    if (rawValue is! String) {
      return null;
    }
    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
