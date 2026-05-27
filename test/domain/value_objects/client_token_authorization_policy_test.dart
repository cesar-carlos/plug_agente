import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/client_token_authorization_policy.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

void main() {
  group('ClientTokenAuthorizationPolicy equality', () {
    const readOnlyOnAlpha = ClientTokenRule(
      resource: DatabaseResource(
        resourceType: DatabaseResourceType.table,
        name: 'dbo.alpha',
      ),
      permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
      effect: ClientTokenRuleEffect.allow,
    );
    const readWriteOnBeta = ClientTokenRule(
      resource: DatabaseResource(
        resourceType: DatabaseResourceType.view,
        name: 'dbo.beta',
      ),
      permissions: ClientPermissionSet(canRead: true, canUpdate: true, canDelete: false),
      effect: ClientTokenRuleEffect.allow,
    );

    test('treats reordered rules as equal', () {
      final left = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.none,
        rules: const [readOnlyOnAlpha, readWriteOnBeta],
      );
      final right = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.none,
        rules: const [readWriteOnBeta, readOnlyOnAlpha],
      );

      expect(left, equals(right));
      expect(left.hashCode, equals(right.hashCode));
    });

    test('treats same rules with different effect as different', () {
      final allow = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.none,
        rules: const [readOnlyOnAlpha],
      );
      final deny = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.none,
        rules: const [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'dbo.alpha',
            ),
            permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
            effect: ClientTokenRuleEffect.deny,
          ),
        ],
      );

      expect(allow, isNot(equals(deny)));
    });

    test('drops resource rules and clears global permissions when global scope is off', () {
      final globalScopeOff = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.fullAccess,
        rules: const [readOnlyOnAlpha],
      );
      final canonical = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.none,
        rules: const [readOnlyOnAlpha],
      );

      expect(globalScopeOff, equals(canonical));
    });

    test('treats different scope flags as different policies', () {
      final tables = ClientTokenAuthorizationPolicy(
        allTables: true,
        allViews: false,
        globalPermissions: ClientPermissionSet.fullAccess,
        rules: const [],
      );
      final views = ClientTokenAuthorizationPolicy(
        allTables: false,
        allViews: true,
        globalPermissions: ClientPermissionSet.fullAccess,
        rules: const [],
      );

      expect(tables, isNot(equals(views)));
    });
  });
}
