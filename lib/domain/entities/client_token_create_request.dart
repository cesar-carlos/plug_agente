import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/client_token_authorization_policy.dart';

class ClientTokenCreateRequest {
  const ClientTokenCreateRequest({
    required this.clientId,
    required bool allTables,
    required bool allViews,
    required this.rules,
    ClientPermissionSet? globalPermissions,
    bool? allPermissions,
    this.name = '',
    this.payload = const <String, dynamic>{},
    this.agentId,
  }) : allTables = allTables || (allPermissions ?? false),
       allViews = allViews || (allPermissions ?? false),
       globalPermissions =
           globalPermissions ??
           ((allPermissions ?? false)
               ? ClientPermissionSet.fullAccess
               : ((allTables || allViews) ? ClientPermissionSet.legacyScopedAccess : ClientPermissionSet.none));

  final String clientId;

  /// User-defined display name for easy identification. Empty when not set.
  final String name;
  final String? agentId;
  final Map<String, dynamic> payload;
  final bool allTables;
  final bool allViews;
  final ClientPermissionSet globalPermissions;
  final List<ClientTokenRule> rules;

  bool get usesGlobalScope => allTables || allViews;

  bool get allPermissions => allTables && allViews && globalPermissions.isFullAccess;

  ClientPermissionSet get effectiveGlobalPermissions => usesGlobalScope ? globalPermissions : ClientPermissionSet.none;

  List<ClientTokenRule> get effectiveRules => usesGlobalScope ? const <ClientTokenRule>[] : rules;

  /// Single source of truth for the authorization policy carried by this
  /// request. Compare with [ClientTokenSummary.policy] to decide whether a
  /// token rotation is required.
  ClientTokenAuthorizationPolicy get policy => ClientTokenAuthorizationPolicy(
    allTables: allTables,
    allViews: allViews,
    globalPermissions: effectiveGlobalPermissions,
    rules: effectiveRules,
  );

  String get normalizedClientId => clientId.trim();
  String get normalizedName => name.trim();
  String? get normalizedAgentId {
    final trimmed = agentId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Returns true when this request changes the authorization policy compared
  /// with [current], i.e. token scope, global permissions, or resource rules.
  /// Pure metadata fields (clientId, name, agentId, payload) are ignored on
  /// purpose: editing them must not rotate the underlying token secret.
  bool changesAuthorizationPolicyFrom(ClientTokenSummary current) {
    return policy != current.policy;
  }

  /// Returns true when any non-policy metadata differs from [current]. Used to
  /// decide whether to write the row at all and which audit event to record.
  bool changesMetadataFrom(ClientTokenSummary current) {
    if (normalizedClientId != current.clientId) {
      return true;
    }
    if (normalizedName != current.name) {
      return true;
    }
    if (normalizedAgentId != current.agentId) {
      return true;
    }
    return !_payloadsEqual(payload, current.payload);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'client_id': clientId,
      if (name.isNotEmpty) 'name': name,
      if (agentId != null) 'agent_id': agentId,
      'payload': payload,
      'all_tables': allTables,
      'all_views': allViews,
      'global_permissions': effectiveGlobalPermissions.toJson(),
      'all_permissions': allPermissions,
      'rules': effectiveRules.map((rule) => rule.toJson()).toList(),
    };
  }
}

bool _payloadsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key)) {
      return false;
    }
    if (!_valuesEqual(entry.value, right[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _valuesEqual(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    return _payloadsEqual(
      Map<String, dynamic>.from(a),
      Map<String, dynamic>.from(b),
    );
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_valuesEqual(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
