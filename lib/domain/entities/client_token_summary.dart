import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/client_token_authorization_policy.dart';

class ClientTokenSummary {
  const ClientTokenSummary({
    required this.id,
    required this.clientId,
    required this.createdAt,
    required this.isRevoked,
    required bool allTables,
    required bool allViews,
    required this.rules,
    ClientPermissionSet? globalPermissions,
    bool? allPermissions,
    this.name = '',
    this.version = 1,
    this.updatedAt,
    this.agentId,
    this.payload = const <String, dynamic>{},
    this.tokenValue,
  }) : allTables = allTables || (allPermissions ?? false),
       allViews = allViews || (allPermissions ?? false),
       globalPermissions =
           globalPermissions ??
           ((allPermissions ?? false)
               ? ClientPermissionSet.fullAccess
               : ((allTables || allViews) ? ClientPermissionSet.legacyScopedAccess : ClientPermissionSet.none));

  factory ClientTokenSummary.fromJson(Map<String, dynamic> json) {
    final policyJson = json['policy'] as Map<String, dynamic>?;
    final source = policyJson ?? json;
    final rawRules = source['rules'] as List<dynamic>? ?? const <dynamic>[];
    final parsedRules = rawRules
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .map(ClientTokenRule.fromJson)
        .toList();
    final legacyAllPermissions = source['all_permissions'] as bool? ?? false;
    final createdAt = _parseDateTime(
      source['created_at'] ?? json['created_at'],
    );
    final payload = _parsePayload(source['payload']);

    return ClientTokenSummary(
      id: source['id'] as String? ?? json['id'] as String? ?? '',
      clientId: source['client_id'] as String? ?? json['client_id'] as String? ?? '',
      name: source['name'] as String? ?? json['name'] as String? ?? '',
      createdAt: createdAt,
      isRevoked: source['is_revoked'] as bool? ?? json['is_revoked'] as bool? ?? false,
      version: source['version'] as int? ?? json['version'] as int? ?? 1,
      updatedAt: _parseDateTimeOrNull(
        source['updated_at'] ?? json['updated_at'],
      ),
      agentId: source['agent_id'] as String?,
      payload: payload,
      tokenValue: source['token_value'] as String? ?? json['token_value'] as String?,
      allTables: source['all_tables'] as bool? ?? legacyAllPermissions,
      allViews: source['all_views'] as bool? ?? legacyAllPermissions,
      globalPermissions: _parseGlobalPermissions(source),
      allPermissions: legacyAllPermissions,
      rules: parsedRules,
    );
  }

  static const Object _unset = Object();

  final String id;
  final String clientId;

  /// User-defined display name for easy identification. Empty when not set.
  final String name;
  final DateTime createdAt;
  final bool isRevoked;
  final int version;
  final DateTime? updatedAt;
  final String? agentId;
  final Map<String, dynamic> payload;
  final String? tokenValue;
  final bool allTables;
  final bool allViews;
  final ClientPermissionSet globalPermissions;
  final List<ClientTokenRule> rules;

  bool get allPermissions => allTables && allViews && globalPermissions.isFullAccess;

  /// Authorization policy snapshot used to compare with edit requests when
  /// deciding whether the underlying token must be rotated.
  ClientTokenAuthorizationPolicy get policy => ClientTokenAuthorizationPolicy(
    allTables: allTables,
    allViews: allViews,
    globalPermissions: globalPermissions,
    rules: rules,
  );

  ClientTokenSummary copyWith({
    String? id,
    String? clientId,
    String? name,
    DateTime? createdAt,
    bool? isRevoked,
    int? version,
    Object? updatedAt = _unset,
    Object? agentId = _unset,
    Map<String, dynamic>? payload,
    Object? tokenValue = _unset,
    bool? allTables,
    bool? allViews,
    ClientPermissionSet? globalPermissions,
    List<ClientTokenRule>? rules,
  }) {
    return ClientTokenSummary(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      isRevoked: isRevoked ?? this.isRevoked,
      version: version ?? this.version,
      updatedAt: identical(updatedAt, _unset) ? this.updatedAt : updatedAt as DateTime?,
      agentId: identical(agentId, _unset) ? this.agentId : agentId as String?,
      payload: payload ?? this.payload,
      tokenValue: identical(tokenValue, _unset) ? this.tokenValue : tokenValue as String?,
      allTables: allTables ?? this.allTables,
      allViews: allViews ?? this.allViews,
      globalPermissions: globalPermissions ?? this.globalPermissions,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'client_id': clientId,
      if (name.isNotEmpty) 'name': name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_revoked': isRevoked,
      'version': version,
      if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      if (agentId != null) 'agent_id': agentId,
      'payload': payload,
      if (tokenValue != null) 'token_value': tokenValue,
      'all_tables': allTables,
      'all_views': allViews,
      'global_permissions': globalPermissions.toJson(),
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
    // Explicit epoch sentinel when the hub sends an absent or unparseable
    // created_at. Callers should treat DateTime.utc(1970) as "unknown" for
    // display and sort purposes rather than a real creation time.
    return DateTime.utc(1970);
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
}
