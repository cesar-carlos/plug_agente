// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: Immutable value object compares by value for equality.

import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';

/// Authorization policy carried by a client token: scope flags, global
/// permissions and per-resource rules.
///
/// Two policies are equal when they grant the same access regardless of the
/// order resource rules were configured. This is the single source of truth
/// for deciding when a token must be rotated on edit.
class ClientTokenAuthorizationPolicy {
  ClientTokenAuthorizationPolicy({
    required this.allTables,
    required this.allViews,
    required this.globalPermissions,
    required List<ClientTokenRule> rules,
  }) : rules = List<ClientTokenRule>.unmodifiable(rules);

  final bool allTables;
  final bool allViews;
  final ClientPermissionSet globalPermissions;
  final List<ClientTokenRule> rules;

  bool get usesGlobalScope => allTables || allViews;

  /// Effective rules considering global scope precedence: when global scope
  /// is enabled the resource rules are dropped, matching server-side
  /// authorization semantics.
  List<ClientTokenRule> get effectiveRules => usesGlobalScope ? const <ClientTokenRule>[] : rules;

  /// Effective global permissions: zeroed out when global scope is disabled.
  ClientPermissionSet get effectiveGlobalPermissions => usesGlobalScope ? globalPermissions : ClientPermissionSet.none;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ClientTokenAuthorizationPolicy) {
      return false;
    }
    if (other.allTables != allTables || other.allViews != allViews) {
      return false;
    }
    if (other.effectiveGlobalPermissions != effectiveGlobalPermissions) {
      return false;
    }

    final left = effectiveRules;
    final right = other.effectiveRules;
    if (left.length != right.length) {
      return false;
    }

    // Order-insensitive comparison: rules are semantically a set of
    // resource→permission grants. Reordering the same rules in the UI must
    // not be treated as a policy change.
    final leftSorted = List<ClientTokenRule>.of(left)..sort(_compareRules);
    final rightSorted = List<ClientTokenRule>.of(right)..sort(_compareRules);
    for (var i = 0; i < leftSorted.length; i++) {
      if (leftSorted[i] != rightSorted[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    final sortedRules = List<ClientTokenRule>.of(effectiveRules)..sort(_compareRules);
    return Object.hash(
      allTables,
      allViews,
      effectiveGlobalPermissions,
      Object.hashAll(sortedRules),
    );
  }

  static int _compareRules(ClientTokenRule a, ClientTokenRule b) {
    final byType = a.resource.resourceType.index.compareTo(b.resource.resourceType.index);
    if (byType != 0) {
      return byType;
    }
    final byName = a.resource.normalizedName.compareTo(b.resource.normalizedName);
    if (byName != 0) {
      return byName;
    }
    return a.effect.index.compareTo(b.effect.index);
  }
}
