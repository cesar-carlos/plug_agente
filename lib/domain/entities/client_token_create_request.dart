import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';

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
