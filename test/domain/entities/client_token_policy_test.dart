import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

void main() {
  group('ClientTokenPolicy.isAllowed', () {
    const clientId = 'test-client';

    test('should deny all operations when token is revoked', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: true,
        allViews: true,
        allPermissions: true,
        isRevoked: true,
        rules: [],
      );

      final result = policy.isAllowed(
        operation: SqlOperation.read,
        resource: const DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'users',
        ),
      );

      check(result).isFalse();
    });

    test('should allow all operations when allPermissions is true', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: false,
        allViews: false,
        allPermissions: true,
        rules: [],
      );

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'users',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.update,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.view,
            name: 'active_users',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.delete,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.unknown,
            name: 'some_resource',
          ),
        ),
      ).isTrue();
    });

    test('should deny when deny rule matches, even with allPermissions', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: true,
        allViews: true,
        allPermissions: true,
        rules: [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'sensitive',
            ),
            permissions: ClientPermissionSet(
              canRead: true,
              canUpdate: true,
              canDelete: true,
            ),
            effect: ClientTokenRuleEffect.deny,
          ),
        ],
      );

      final result = policy.isAllowed(
        operation: SqlOperation.read,
        resource: const DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'sensitive',
        ),
      );

      check(result).isFalse();
    });

    test('should allow when allow rule matches', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'users',
            ),
            permissions: ClientPermissionSet(
              canRead: true,
              canUpdate: false,
              canDelete: false,
            ),
            effect: ClientTokenRuleEffect.allow,
          ),
        ],
      );

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'users',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'dbo.users',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: '[DBO].[USERS]',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.update,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'users',
          ),
        ),
      ).isFalse();
    });

    test('should match resource key ignoring case and quoting', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: '"Dbo"."Cliente"',
            ),
            permissions: ClientPermissionSet(
              canRead: true,
              canUpdate: false,
              canDelete: false,
            ),
            effect: ClientTokenRuleEffect.allow,
          ),
        ],
      );

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'cliente',
          ),
        ),
      ).isTrue();
    });

    test('should deny when operation does not match allow rule', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'users',
            ),
            permissions: ClientPermissionSet(
              canRead: true,
              canUpdate: false,
              canDelete: false,
            ),
            effect: ClientTokenRuleEffect.allow,
          ),
        ],
      );

      final result = policy.isAllowed(
        operation: SqlOperation.delete,
        resource: const DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'users',
        ),
      );

      check(result).isFalse();
    });

    test('should allow all tables when allTables is true', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: true,
        allViews: false,
        allPermissions: false,
        rules: [],
      );

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'any_table',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.view,
            name: 'any_view',
          ),
        ),
      ).isFalse();
    });

    test('should allow all views when allViews is true', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: false,
        allViews: true,
        allPermissions: false,
        rules: [],
      );

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.view,
            name: 'any_view',
          ),
        ),
      ).isTrue();

      check(
        policy.isAllowed(
          operation: SqlOperation.read,
          resource: const DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'any_table',
          ),
        ),
      ).isFalse();
    });

    test(
      'should allow unknown resources when allTables or allViews is true',
      () {
        const policyWithTables = ClientTokenPolicy(
          clientId: clientId,
          allTables: true,
          allViews: false,
          allPermissions: false,
          rules: [],
        );

        check(
          policyWithTables.isAllowed(
            operation: SqlOperation.read,
            resource: const DatabaseResource(
              resourceType: DatabaseResourceType.unknown,
              name: 'unknown_resource',
            ),
          ),
        ).isTrue();

        const policyWithViews = ClientTokenPolicy(
          clientId: clientId,
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: [],
        );

        check(
          policyWithViews.isAllowed(
            operation: SqlOperation.read,
            resource: const DatabaseResource(
              resourceType: DatabaseResourceType.unknown,
              name: 'unknown_resource',
            ),
          ),
        ).isTrue();
      },
    );

    test('should prioritize deny over allow rules', () {
      const policy = ClientTokenPolicy(
        clientId: clientId,
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: [
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'users',
            ),
            permissions: ClientPermissionSet(
              canRead: true,
              canUpdate: true,
              canDelete: true,
            ),
            effect: ClientTokenRuleEffect.allow,
          ),
          ClientTokenRule(
            resource: DatabaseResource(
              resourceType: DatabaseResourceType.table,
              name: 'users',
            ),
            permissions: ClientPermissionSet(
              canRead: true,
              canUpdate: false,
              canDelete: false,
            ),
            effect: ClientTokenRuleEffect.deny,
          ),
        ],
      );

      final result = policy.isAllowed(
        operation: SqlOperation.read,
        resource: const DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'users',
        ),
      );

      check(result).isFalse();
    });

    test('toJson serializes policy fields', () {
      const policy = ClientTokenPolicy(
        clientId: 'c1',
        agentId: 'a1',
        payload: <String, dynamic>{'k': 1},
        allTables: true,
        allViews: false,
        allPermissions: false,
        rules: [
          ClientTokenRule(
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
          ),
        ],
      );

      check(policy.toJson()).deepEquals(<String, dynamic>{
        'client_id': 'c1',
        'agent_id': 'a1',
        'payload': <String, dynamic>{'k': 1},
        'all_tables': true,
        'all_views': false,
        'all_permissions': false,
        'is_revoked': false,
        'rules': [
          <String, dynamic>{
            'resource_type': 'table',
            'resource': 't',
            'effect': 'allow',
            'read': true,
            'update': false,
            'delete': false,
          },
        ],
      });
    });
  });
}
