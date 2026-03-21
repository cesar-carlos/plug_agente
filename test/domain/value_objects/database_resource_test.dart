import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';

void main() {
  group('DatabaseResource', () {
    test('fromJson maps table type', () {
      final r = DatabaseResource.fromJson(const <String, dynamic>{
        'resource_type': 'table',
        'resource': 'dbo.Users',
      });
      expect(r.resourceType, DatabaseResourceType.table);
      expect(r.normalizedName, equals('dbo.users'));
    });

    test('fromJson maps view type', () {
      final r = DatabaseResource.fromJson(const <String, dynamic>{
        'resource_type': 'view',
        'resource': 'v_active',
      });
      expect(r.resourceType, DatabaseResourceType.view);
      expect(r.normalizedName, equals('v_active'));
    });

    test('fromJson defaults unknown type', () {
      final r = DatabaseResource.fromJson(const <String, dynamic>{
        'resource_type': 'other',
        'resource': 'x',
      });
      expect(r.resourceType, DatabaseResourceType.unknown);
    });

    test('fromJson handles missing keys', () {
      final r = DatabaseResource.fromJson(const <String, dynamic>{});
      expect(r.resourceType, DatabaseResourceType.unknown);
      expect(r.normalizedName, isEmpty);
    });

    test('toJson includes normalized resource', () {
      const r = DatabaseResource(
        resourceType: DatabaseResourceType.table,
        name: 'T1',
      );
      expect(r.toJson(), equals(<String, dynamic>{
        'resource_type': 'table',
        'resource': 't1',
      }));
    });

    test('equality uses type and normalized name', () {
      const a = DatabaseResource(
        resourceType: DatabaseResourceType.table,
        name: 'A',
      );
      const b = DatabaseResource(
        resourceType: DatabaseResourceType.table,
        name: 'a',
      );
      const c = DatabaseResource(
        resourceType: DatabaseResourceType.view,
        name: 'a',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('matches accepts schema-qualified and base name', () {
      const r = DatabaseResource(
        resourceType: DatabaseResourceType.table,
        name: 'dbo.orders',
      );
      expect(r.matches('orders'), isTrue);
      expect(r.matches('dbo.orders'), isTrue);
      expect(r.matches('other'), isFalse);
    });
  });
}
