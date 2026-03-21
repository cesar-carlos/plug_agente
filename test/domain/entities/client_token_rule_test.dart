import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

void main() {
  group('ClientTokenRule', () {
    test('fromJson defaults effect to allow', () {
      final rule = ClientTokenRule.fromJson(<String, dynamic>{
        'resource_type': 'table',
        'resource': 't1',
        'read': true,
      });
      expect(rule.effect, ClientTokenRuleEffect.allow);
      expect(rule.resource.normalizedName, equals('t1'));
      expect(rule.permissions.canRead, isTrue);
    });

    test('fromJson parses deny effect case-insensitively', () {
      final rule = ClientTokenRule.fromJson(<String, dynamic>{
        'resource_type': 'view',
        'resource': 'v1',
        'effect': 'DENY',
        'delete': true,
      });
      expect(rule.effect, ClientTokenRuleEffect.deny);
    });

    test('toJson merges resource, effect and permissions', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'x',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: true,
        ),
        effect: ClientTokenRuleEffect.deny,
      );
      expect(
        rule.toJson(),
        equals(<String, dynamic>{
          'resource_type': 'table',
          'resource': 'x',
          'effect': 'deny',
          'read': true,
          'update': false,
          'delete': true,
        }),
      );
    });

    test('appliesTo is false when name does not match', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'a',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: true,
          canDelete: true,
        ),
        effect: ClientTokenRuleEffect.allow,
      );
      expect(
        rule.appliesTo(
          const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'b',
          ),
        ),
        isFalse,
      );
    });

    test('appliesTo rejects view rule for table-only target', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.view,
          name: 'v1',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      );
      expect(
        rule.appliesTo(
          const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'v1',
          ),
        ),
        isFalse,
      );
    });

    test('appliesTo rejects table rule for view-only target', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 't1',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      );
      expect(
        rule.appliesTo(
          const DatabaseResource(
            resourceType: DatabaseResourceType.view,
            name: 't1',
          ),
        ),
        isFalse,
      );
    });

    test('appliesTo allows unknown resource type when name matches', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 't1',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      );
      expect(
        rule.appliesTo(
          const DatabaseResource(
            resourceType: DatabaseResourceType.unknown,
            name: 't1',
          ),
        ),
        isTrue,
      );
    });

    test('unknown rule resource type matches table target', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.unknown,
          name: 't1',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      );
      expect(
        rule.appliesTo(
          const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 't1',
          ),
        ),
        isTrue,
      );
    });

    test('affectsOperation delegates to permissions', () {
      const rule = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 't',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      );
      expect(rule.affectsOperation(SqlOperation.read), isTrue);
      expect(rule.affectsOperation(SqlOperation.update), isFalse);
    });
  });
}
