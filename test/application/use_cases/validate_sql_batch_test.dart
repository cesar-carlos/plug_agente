import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/validate_sql_batch.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

void main() {
  group('ValidateSqlBatch', () {
    const validator = ValidateSqlBatch();

    test('should accept valid batch commands', () {
      final result = validator([
        const SqlCommand(sql: 'SELECT 1'),
        const SqlCommand(sql: 'UPDATE t SET x = 1'),
      ]);

      expect(result.isSuccess(), isTrue);
    });

    test('should fail fast on first invalid command', () {
      final result = validator([
        const SqlCommand(sql: 'SELECT 1'),
        const SqlCommand(sql: 'DROP TABLE users; SELECT 1'),
        const SqlCommand(sql: 'SELECT 2'),
      ]);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('expected failure'),
        (failure) {
          final validationFailure = failure as domain.ValidationFailure;
          expect(validationFailure.context['operation'], 'batch_validation');
          expect(validationFailure.context['index'], 1);
        },
      );
    });
  });
}
