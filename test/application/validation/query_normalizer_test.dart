import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/application/validation/query_normalizer.dart';

void main() {
  group('QueryNormalizer', () {
    late QueryNormalizer normalizer;

    setUp(() {
      normalizer = QueryNormalizer();
    });

    group('isValidQuery', () {
      test('should return true for valid SELECT query', () {
        // Arrange
        const query = 'SELECT * FROM users';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isTrue);
      });

      test('should return false for DROP query', () {
        // Arrange
        const query = 'DROP TABLE users';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should return false for TRUNCATE query', () {
        // Arrange
        const query = 'TRUNCATE TABLE users';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should return false for ALTER query', () {
        // Arrange
        const query = 'ALTER TABLE users ADD COLUMN age INT';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should return false for CREATE query', () {
        // Arrange
        const query = 'CREATE TABLE users (id INT)';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should return false for DELETE without WHERE', () {
        // Arrange
        const query = 'DELETE FROM users';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should return true for DELETE with WHERE', () {
        // Arrange
        const query = 'DELETE FROM users WHERE id = 1';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isTrue);
      });

      test('should return false for empty query', () {
        // Arrange
        const query = '';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should be case-insensitive', () {
        // Arrange
        const query = 'drop table users';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });

      test('should handle whitespace', () {
        // Arrange
        const query = '  DROP   TABLE  users  ';

        // Act
        final result = normalizer.isValidQuery(query);

        // Assert
        expect(result, isFalse);
      });
    });

    group('sanitizeQuery', () {
      test('should remove extra whitespace', () {
        // Arrange
        const query = 'SELECT   *   FROM   users';

        // Act
        final result = normalizer.sanitizeQuery(query);

        // Assert
        expect(result, 'SELECT * FROM users');
      });

      test('should trim leading and trailing whitespace', () {
        // Arrange
        const query = '   SELECT * FROM users   ';

        // Act
        final result = normalizer.sanitizeQuery(query);

        // Assert
        expect(result, 'SELECT * FROM users');
      });

      test('should replace newlines and tabs with spaces', () {
        // Arrange
        const query = 'SELECT *\nFROM\tusers';

        // Act
        final result = normalizer.sanitizeQuery(query);

        // Assert
        expect(result, 'SELECT * FROM users');
      });

      test('should return empty string for empty input', () {
        // Arrange
        const query = '';

        // Act
        final result = normalizer.sanitizeQuery(query);

        // Assert
        expect(result, '');
      });

      test('should handle multiple spaces', () {
        // Arrange
        const query = 'SELECT    *    FROM    users    WHERE    id    =    1';

        // Act
        final result = normalizer.sanitizeQuery(query);

        // Assert
        expect(result, 'SELECT * FROM users WHERE id = 1');
      });
    });
  });
}
