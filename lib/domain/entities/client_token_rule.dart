// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: Immutable value object compares by value for equality.

import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

enum ClientTokenRuleEffect {
  allow,
  deny,
}

class ClientTokenRule {
  const ClientTokenRule({
    required this.resource,
    required this.permissions,
    required this.effect,
  });

  factory ClientTokenRule.fromJson(Map<String, dynamic> json) {
    final effectValue = (json['effect'] as String? ?? 'allow').toLowerCase();
    return ClientTokenRule(
      resource: DatabaseResource.fromJson(json),
      permissions: ClientPermissionSet.fromJson(json),
      effect: effectValue == 'deny' ? ClientTokenRuleEffect.deny : ClientTokenRuleEffect.allow,
    );
  }

  final DatabaseResource resource;
  final ClientPermissionSet permissions;
  final ClientTokenRuleEffect effect;

  bool appliesTo(DatabaseResource target) {
    if (!resource.matches(target.name)) {
      return false;
    }

    return switch (target.resourceType) {
      DatabaseResourceType.table =>
        resource.resourceType == DatabaseResourceType.table || resource.resourceType == DatabaseResourceType.unknown,
      DatabaseResourceType.view =>
        resource.resourceType == DatabaseResourceType.view || resource.resourceType == DatabaseResourceType.unknown,
      DatabaseResourceType.unknown => true,
    };
  }

  bool affectsOperation(SqlOperation operation) {
    return permissions.allows(operation);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...resource.toJson(),
      'effect': effect.name,
      ...permissions.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ClientTokenRule &&
        other.resource == resource &&
        other.permissions == permissions &&
        other.effect == effect;
  }

  @override
  int get hashCode => Object.hash(resource, permissions, effect);
}
