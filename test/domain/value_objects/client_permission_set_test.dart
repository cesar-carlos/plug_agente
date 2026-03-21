import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';

void main() {
  group('ClientPermissionSet', () {
    test('fromJson uses defaults for absent flags', () {
      final set = ClientPermissionSet.fromJson(<String, dynamic>{});
      expect(set.canRead, isFalse);
      expect(set.canUpdate, isFalse);
      expect(set.canDelete, isFalse);
    });

    test('fromJson reads explicit flags', () {
      final set = ClientPermissionSet.fromJson(<String, dynamic>{
        'read': true,
        'update': true,
        'delete': false,
      });
      expect(set.canRead, isTrue);
      expect(set.canUpdate, isTrue);
      expect(set.canDelete, isFalse);
    });

    test('allows maps operations to flags', () {
      const full = ClientPermissionSet(
        canRead: true,
        canUpdate: true,
        canDelete: true,
      );
      expect(full.allows(SqlOperation.read), isTrue);
      expect(full.allows(SqlOperation.update), isTrue);
      expect(full.allows(SqlOperation.delete), isTrue);

      const readOnly = ClientPermissionSet(
        canRead: true,
        canUpdate: false,
        canDelete: false,
      );
      expect(readOnly.allows(SqlOperation.read), isTrue);
      expect(readOnly.allows(SqlOperation.update), isFalse);
      expect(readOnly.allows(SqlOperation.delete), isFalse);
    });

    test('toJson round-trips keys', () {
      const original = ClientPermissionSet(
        canRead: false,
        canUpdate: true,
        canDelete: true,
      );
      final decoded = ClientPermissionSet.fromJson(original.toJson());
      expect(decoded.canRead, isFalse);
      expect(decoded.canUpdate, isTrue);
      expect(decoded.canDelete, isTrue);
    });
  });
}
