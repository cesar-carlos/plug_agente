import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';

void main() {
  group('SqlOperationClassifier', () {
    late SqlOperationClassifier classifier;

    setUp(() {
      classifier = SqlOperationClassifier();
    });

    test('should classify SELECT as read', () {
      final result = classifier.classify('SELECT * FROM dbo.users');

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should classify UPDATE as update', () {
      final result = classifier.classify(
        'UPDATE dbo.users SET name = "John" WHERE id = 1',
      );

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should classify DELETE as delete', () {
      final result = classifier.classify('DELETE FROM dbo.users WHERE id = 1');

      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.delete));
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should fail on multiple statements', () {
      final result = classifier.classify(
        'SELECT * FROM users; DELETE FROM users WHERE id = 1',
      );

      expect(result.isError(), isTrue);
    });

    test('should allow semicolon inside string literal', () {
      final result = classifier.classify(
        "SELECT * FROM dbo.users WHERE note = ';'",
      );

      expect(result.isSuccess(), isTrue);
    });
  });
}
