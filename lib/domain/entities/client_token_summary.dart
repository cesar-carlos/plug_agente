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
    this.version = 1,
    this.updatedAt,
    this.agentId,
    this.payload = const <String, dynamic>{},
    this.tokenValue,
  });

  factory ClientTokenSummary.fromJson(Map<String, dynamic> json) {
    final policyJson = json['policy'] as Map<String, dynamic>?;
    final source = policyJson ?? json;
    final rawRules = source['rules'] as List<dynamic>? ?? const <dynamic>[];
    final parsedRules = rawRules
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .map(ClientTokenRule.fromJson)
        .toList();
    final createdAt = _parseDateTime(
      source['created_at'] ?? json['created_at'],
    );
    final payload = _parsePayload(source['payload']);

    return ClientTokenSummary(
      id: source['id'] as String? ?? json['id'] as String? ?? '',
      clientId: source['client_id'] as String? ?? json['client_id'] as String? ?? '',
      createdAt: createdAt,
      isRevoked: source['is_revoked'] as bool? ?? json['is_revoked'] as bool? ?? false,
      version: source['version'] as int? ?? json['version'] as int? ?? 1,
      updatedAt: _parseDateTimeOrNull(
        source['updated_at'] ?? json['updated_at'],
      ),
      agentId: source['agent_id'] as String?,
      payload: payload,
      tokenValue: source['token_value'] as String? ?? json['token_value'] as String?,
      allTables: source['all_tables'] as bool? ?? false,
      allViews: source['all_views'] as bool? ?? false,
      allPermissions: source['all_permissions'] as bool? ?? false,
      rules: parsedRules,
    );
  }

  static const Object _unset = Object();

  final String id;
  final String clientId;
  final DateTime createdAt;
  final bool isRevoked;
  final int version;
  final DateTime? updatedAt;
  final String? agentId;
  final Map<String, dynamic> payload;
  final String? tokenValue;
  final bool allTables;
  final bool allViews;
  final bool allPermissions;
  final List<ClientTokenRule> rules;

  ClientTokenSummary copyWith({
    String? id,
    String? clientId,
    DateTime? createdAt,
    bool? isRevoked,
    int? version,
    Object? updatedAt = _unset,
    Object? agentId = _unset,
    Map<String, dynamic>? payload,
    Object? tokenValue = _unset,
    bool? allTables,
    bool? allViews,
    bool? allPermissions,
    List<ClientTokenRule>? rules,
  }) {
    return ClientTokenSummary(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      createdAt: createdAt ?? this.createdAt,
      isRevoked: isRevoked ?? this.isRevoked,
      version: version ?? this.version,
      updatedAt: identical(updatedAt, _unset) ? this.updatedAt : updatedAt as DateTime?,
      agentId: identical(agentId, _unset) ? this.agentId : agentId as String?,
      payload: payload ?? this.payload,
      tokenValue: identical(tokenValue, _unset) ? this.tokenValue : tokenValue as String?,
      allTables: allTables ?? this.allTables,
      allViews: allViews ?? this.allViews,
      allPermissions: allPermissions ?? this.allPermissions,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'client_id': clientId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_revoked': isRevoked,
      'version': version,
      if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      if (agentId != null) 'agent_id': agentId,
      'payload': payload,
      if (tokenValue != null) 'token_value': tokenValue,
      'all_tables': allTables,
      'all_views': allViews,
      'all_permissions': allPermissions,
      'rules': rules.map((rule) => rule.toJson()).toList(),
    };
  }

  static DateTime _parseDateTime(Object? rawValue) {
    if (rawValue is String) {
      final parsed = DateTime.tryParse(rawValue);
      if (parsed != null) {
        return parsed;
      }
    }
    if (rawValue is int) {
      final millisecondsSinceEpoch = rawValue > 9999999999 ? rawValue : rawValue * 1000;
      return DateTime.fromMillisecondsSinceEpoch(
        millisecondsSinceEpoch,
        isUtc: true,
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static DateTime? _parseDateTimeOrNull(Object? rawValue) {
    if (rawValue == null) {
      return null;
    }
    return _parseDateTime(rawValue);
  }

  static Map<String, dynamic> _parsePayload(Object? rawValue) {
    if (rawValue is Map<dynamic, dynamic>) {
      return Map<String, dynamic>.from(rawValue);
    }
    return const <String, dynamic>{};
  }
}
