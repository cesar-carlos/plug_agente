import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';

/// Test matrix for SQL validation and classification (Fase 4).
void main() {
  group('SqlValidator.validateSqlForExecution', () {
    group('SELECT', () {
      test('should accept simple SELECT', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT * FROM dbo.users',
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept SELECT with JOIN', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT u.id, o.name FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept SELECT with subquery', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT * FROM dbo.users WHERE id IN (SELECT user_id FROM dbo.orders)',
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept SELECT with CTE (WITH)', () {
        final r = SqlValidator.validateSqlForExecution(
          'WITH cte AS (SELECT 1 AS n) SELECT * FROM cte',
        );
        expect(r.isSuccess(), isTrue);
      });
    });

    group('UPDATE', () {
      test('should accept simple UPDATE', () {
        final r = SqlValidator.validateSqlForExecution(
          "UPDATE dbo.users SET name = 'x' WHERE id = 1",
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept UPDATE with JOIN', () {
        final r = SqlValidator.validateSqlForExecution(
          'UPDATE u SET u.name = o.code FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );
        expect(r.isSuccess(), isTrue);
      });
    });

    group('DELETE', () {
      test('should accept simple DELETE', () {
        final r = SqlValidator.validateSqlForExecution(
          'DELETE FROM dbo.users WHERE id = 1',
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept DELETE with alias and schema', () {
        final r = SqlValidator.validateSqlForExecution(
          'DELETE t FROM dbo.tabela t WHERE t.id = 1',
        );
        expect(r.isSuccess(), isTrue);
      });
    });

    group('INSERT and MERGE', () {
      test('should accept INSERT', () {
        final r = SqlValidator.validateSqlForExecution(
          "INSERT INTO dbo.users (name) VALUES ('x')",
        );
        expect(r.isSuccess(), isTrue);
      });

      test('should accept MERGE', () {
        final r = SqlValidator.validateSqlForExecution(
          'MERGE INTO dbo.target t USING dbo.source s ON t.id = s.id WHEN MATCHED THEN UPDATE SET t.x = s.x',
        );
        expect(r.isSuccess(), isTrue);
      });
    });

    group('ambiguous / multi-statement (deny by default)', () {
      test('should reject multiple statements', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT * FROM users; DELETE FROM users',
        );
        expect(r.isError(), isTrue);
      });

      test('should reject DROP', () {
        final r = SqlValidator.validateSqlForExecution('DROP TABLE users');
        expect(r.isError(), isTrue);
      });

      test('should reject ALTER', () {
        final r = SqlValidator.validateSqlForExecution(
          'ALTER TABLE users ADD x INT',
        );
        expect(r.isError(), isTrue);
      });

      test('should reject TRUNCATE', () {
        final r = SqlValidator.validateSqlForExecution('TRUNCATE TABLE users');
        expect(r.isError(), isTrue);
      });

      test('should reject query with line comment', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT * FROM users -- DROP TABLE',
        );
        expect(r.isError(), isTrue);
      });

      test('should reject query with block comment', () {
        final r = SqlValidator.validateSqlForExecution(
          'SELECT /* DROP */ * FROM users',
        );
        expect(r.isError(), isTrue);
      });
    });
  });

  group('SqlValidator.validatePaginationQuery', () {
    test('should require explicit order by', () {
      final result = SqlValidator.validatePaginationQuery(
        'SELECT * FROM dbo.users',
      );

      expect(result.isError(), isTrue);
    });

    test('should parse simple order by terms for deterministic pagination', () {
      final result = SqlValidator.validatePaginationQuery(
        'SELECT id, created_at FROM dbo.users ORDER BY created_at DESC, id ASC',
      );

      expect(result.isSuccess(), isTrue);
      final plan = result.getOrNull()!;
      expect(plan.orderBy, hasLength(2));
      expect(plan.orderBy.first.expression, 'created_at');
      expect(plan.orderBy.first.lookupKey, 'created_at');
      expect(plan.orderBy.first.descending, isTrue);
      expect(plan.orderBy.last.expression, 'id');
      expect(plan.orderBy.last.descending, isFalse);
    });

    test('should strip top-level order by from query before pagination', () {
      final stripped = SqlValidator.stripTopLevelOrderBy(
        'SELECT * FROM dbo.Cliente ORDER BY CodCliente DESC;',
      );

      expect(stripped, equals('SELECT * FROM dbo.Cliente'));
    });

    test('should keep nested order by when stripping only top-level order by', () {
      final stripped = SqlValidator.stripTopLevelOrderBy(
        'SELECT * FROM (SELECT TOP 10 * FROM dbo.Cliente ORDER BY CodCliente DESC) q ORDER BY q.CodCliente ASC',
      );

      expect(
        stripped,
        equals(
          'SELECT * FROM (SELECT TOP 10 * FROM dbo.Cliente ORDER BY CodCliente DESC) q',
        ),
      );
    });
  });

  group('SqlOperationClassifier', () {
    late SqlOperationClassifier classifier;

    setUp(() {
      classifier = SqlOperationClassifier();
    });

    group('SELECT', () {
      test('should classify simple SELECT as read', () {
        final r = classifier.classify('SELECT * FROM dbo.users');
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            expect(c.operation, equals(SqlOperation.read));
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.users'),
              isTrue,
            );
          },
          (_) => fail('Expected success'),
        );
      });

      test('should classify SELECT with JOIN', () {
        final r = classifier.classify(
          'SELECT * FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            expect(c.operation, equals(SqlOperation.read));
            expect(c.resources.length, greaterThanOrEqualTo(2));
          },
          (_) => fail('Expected success'),
        );
      });

      test('should classify SELECT with CTE', () {
        final r = classifier.classify(
          'WITH cte AS (SELECT * FROM dbo.users) SELECT * FROM cte',
        );
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            expect(c.operation, equals(SqlOperation.read));
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.users'),
              isTrue,
            );
            expect(
              c.resources.any((x) => x.normalizedName == 'cte'),
              isFalse,
            );
          },
          (_) => fail('Expected success'),
        );
      });

      test('should classify JOIN with bracketed identifiers and spaces', () {
        final r = classifier.classify(
          'SELECT * FROM [dbo].[Order Details] od JOIN [dbo].[Cliente] c ON od.CodCliente = c.CodCliente',
        );
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            expect(c.operation, equals(SqlOperation.read));
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.orderdetails'),
              isTrue,
            );
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.cliente'),
              isTrue,
            );
          },
          (_) => fail('Expected success'),
        );
      });

      test('should deduplicate repeated resources', () {
        final r = classifier.classify(
          'SELECT * FROM dbo.users u JOIN dbo.users u2 ON u.id = u2.id',
        );
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            final userResources = c.resources
                .where((x) => x.normalizedName == 'dbo.users')
                .toList();
            expect(userResources.length, 1);
          },
          (_) => fail('Expected success'),
        );
      });
    });

    group('UPDATE', () {
      test('should classify UPDATE with JOIN', () {
        final r = classifier.classify(
          'UPDATE u SET u.x=1 FROM dbo.users u JOIN dbo.orders o ON u.id=o.user_id',
        );
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            expect(c.operation, equals(SqlOperation.update));
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.users'),
              isTrue,
            );
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.orders'),
              isTrue,
            );
            expect(c.resources.any((x) => x.normalizedName == 'u'), isFalse);
          },
          (_) => fail('Expected success'),
        );
      });
    });

    group('DELETE', () {
      test('should classify DELETE with alias and schema', () {
        final r = classifier.classify(
          'DELETE t FROM dbo.tabela t WHERE t.id = 1',
        );
        expect(r.isSuccess(), isTrue);
        r.fold(
          (c) {
            expect(c.operation, equals(SqlOperation.delete));
            expect(
              c.resources.any((x) => x.normalizedName == 'dbo.tabela'),
              isTrue,
            );
          },
          (_) => fail('Expected success'),
        );
      });
    });

    group('multi-statement', () {
      test('should fail on multiple statements', () {
        final r = classifier.classify(
          'SELECT * FROM users; DELETE FROM users',
        );
        expect(r.isError(), isTrue);
      });
    });
  });
}
