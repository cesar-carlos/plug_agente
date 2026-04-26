import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/errors/failures.dart';

void main() {
  group('SqlValidator', () {
    group('validateSelectQuery', () {
      test('should accept valid SELECT query', () {
        // Arrange
        const query = 'SELECT * FROM users';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isSuccess(), isTrue);
      });

      test('should accept valid WITH query (CTE)', () {
        // Arrange
        const query = 'WITH cte AS (SELECT 1) SELECT * FROM cte';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isSuccess(), isTrue);
      });

      test('should reject DROP statement', () {
        // Arrange
        const query = 'DROP TABLE users';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
        result.fold(
          (success) => fail('Should have failed'),
          (failure) => expect(
            failure.toString(),
            contains('Apenas consultas SELECT/WITH são permitidas'),
          ),
        );
      });

      test('should reject DELETE statement', () {
        // Arrange
        const query = 'DELETE FROM users WHERE id = 1';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
      });

      test('should reject INSERT statement', () {
        // Arrange
        const query = 'INSERT INTO users (name) VALUES ("John")';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
      });

      test('should reject UPDATE statement', () {
        // Arrange
        const query = 'UPDATE users SET name = "Jane"';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
      });

      test('should reject query with SQL comment (--)', () {
        // Arrange
        const query = 'SELECT * FROM users -- DROP TABLE users';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
        result.fold(
          (success) => fail('Should have failed'),
          (failure) => expect(
            failure.toString(),
            contains('padrões potencialmente perigosos'),
          ),
        );
      });

      test('should reject query with block comment (/* */)', () {
        // Arrange
        const query = 'SELECT /* DROP TABLE users */ * FROM users';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
      });

      test('should reject query with multiple statements', () {
        // Arrange
        const query = 'SELECT * FROM users; DROP TABLE users';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isError(), isTrue);
      });

      test(
        'should accept DROP substring only inside string literal',
        () {
          const query = "SELECT * FROM t WHERE c = ';DROP TABLE u'";
          final result = SqlValidator.validateSelectQuery(query);
          expect(result.isSuccess(), isTrue);
        },
      );

      test('should reject SELECT with table lock hint', () {
        const query = 'SELECT * FROM users WITH (TABLOCKX)';

        final result = SqlValidator.validateSelectQuery(query);

        expect(result.isError(), isTrue);
      });

      test('should accept SELECT with mixed case', () {
        // Arrange
        const query = 'select * from users';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isSuccess(), isTrue);
      });

      test('should accept SELECT with whitespace', () {
        // Arrange
        const query = '  SELECT   *  FROM  users  ';

        // Act
        final result = SqlValidator.validateSelectQuery(query);

        // Assert
        expect(result.isSuccess(), isTrue);
      });
    });

    group('validateSqlForExecution', () {
      test('should accept UPDATE', () {
        final r = SqlValidator.validateSqlForExecution(
          "UPDATE dbo.users SET name = 'x'",
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept DELETE', () {
        final r = SqlValidator.validateSqlForExecution(
          'DELETE FROM dbo.users WHERE id = 1',
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept INSERT', () {
        final r = SqlValidator.validateSqlForExecution(
          "INSERT INTO dbo.users (name) VALUES ('x')",
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should reject empty', () {
        final r = SqlValidator.validateSqlForExecution('');
        expect(r.isError(), isTrue);
      });

      test('should reject multiple statements', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT 1; DROP TABLE x',
        );
        expect(r.isError(), isTrue);
        r.fold(
          (_) => fail('Should have failed'),
          (failure) {
            final f = failure as ValidationFailure;
            expect(f.context['operation'], equals('sql_validation'));
            expect(f.context['reason'], equals('sql_validation_failed'));
            expect((f.context['user_message'] as String?)?.isNotEmpty, isTrue);
          },
        );
      });

      test('should accept semicolon inside string literal', () {
        final result = SqlValidator.validateSqlForExecution(
          "SELECT * FROM dbo.t WHERE code = ';'",
        );
        expect(result.isSuccess(), isTrue);
      });

      test(
        'should accept semicolon and DROP substring only inside string literal',
        () {
          final result = SqlValidator.validateSqlForExecution(
            "SELECT 1 WHERE msg = ';DROP TABLE x'",
          );
          expect(result.isSuccess(), isTrue);
        },
      );

      test('should reject DROP', () {
        final r = SqlValidator.validateSqlForExecution('DROP TABLE users');
        expect(r.isError(), isTrue);
        r.fold(
          (_) => fail('Should have failed'),
          (failure) {
            final f = failure as ValidationFailure;
            expect(f.context['operation'], equals('sql_validation'));
            expect((f.context['user_message'] as String?)?.isNotEmpty, isTrue);
          },
        );
      });

      test('should reject DML with table lock hint', () {
        final r = SqlValidator.validateSqlForExecution(
          "UPDATE dbo.users WITH (UPDLOCK, HOLDLOCK) SET name = 'x'",
        );

        expect(r.isError(), isTrue);
      });
    });

    group('extractNamedParameters', () {
      test('should extract single named parameter', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = :id';

        // Act
        final params = SqlValidator.extractNamedParameters(query);

        // Assert
        expect(params, ['id']);
      });

      test('should extract multiple named parameters', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = :id AND name = :name';

        // Act
        final params = SqlValidator.extractNamedParameters(query);

        // Assert
        expect(params, containsAll(['id', 'name']));
      });

      test('should deduplicate repeated parameters', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = :id OR name = :id';

        // Act
        final params = SqlValidator.extractNamedParameters(query);

        // Assert
        expect(params, ['id']);
        expect(params.length, 1);
      });

      test('should return empty list when no parameters', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = 1';

        // Act
        final params = SqlValidator.extractNamedParameters(query);

        // Assert
        expect(params, isEmpty);
      });
    });

    group('countPlaceholders', () {
      test('should count single placeholder', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = ?';

        // Act
        final count = SqlValidator.countPlaceholders(query);

        // Assert
        expect(count, 1);
      });

      test('should count multiple placeholders', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = ? AND name = ?';

        // Act
        final count = SqlValidator.countPlaceholders(query);

        // Assert
        expect(count, 2);
      });

      test('should return 0 when no placeholders', () {
        // Arrange
        const query = 'SELECT * FROM users WHERE id = 1';

        // Act
        final count = SqlValidator.countPlaceholders(query);

        // Assert
        expect(count, 0);
      });
    });

    group('removeComments', () {
      test('should remove single line comment', () {
        // Arrange
        const query = 'SELECT * FROM users -- this is a comment\nWHERE id = 1';

        // Act
        final result = SqlValidator.removeComments(query);

        // Assert
        expect(result, contains('SELECT * FROM users'));
        expect(result, isNot(contains('-- this is a comment')));
      });

      test('should remove block comment', () {
        // Arrange
        const query = 'SELECT /* comment */ * FROM users';

        // Act
        final result = SqlValidator.removeComments(query);

        // Assert
        expect(result, contains('SELECT * FROM users'));
        expect(result, isNot(contains('/* comment */')));
      });

      test('should remove multiple block comments', () {
        // Arrange
        const query = 'SELECT /* comment1 */ * FROM /* comment2 */ users';

        // Act
        final result = SqlValidator.removeComments(query);

        // Assert
        expect(result, isNot(contains('/* comment1 */')));
        expect(result, isNot(contains('/* comment2 */')));
      });
    });
  });
}
