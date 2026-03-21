import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/core/utils/sql_keyword_scan.dart';
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

    test('should classify WITH query and strip CTE alias from resources', () {
      final result = classifier.classify(
        'WITH cte AS (SELECT * FROM dbo.base) SELECT * FROM cte',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        final names = value.resources.map((r) => r.normalizedName).toSet();
        expect(names, contains('dbo.base'));
        expect(names, isNot(contains('cte')));
      }, (_) => fail('Expected success'));
    });

    test('should classify WITH RECURSIVE', () {
      final result = classifier.classify(
        'WITH RECURSIVE cte AS (SELECT * FROM dbo.base) SELECT * FROM cte',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.read));
        expect(
          value.resources.map((r) => r.normalizedName),
          contains('dbo.base'),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify INSERT INTO', () {
      final result = classifier.classify(
        'INSERT INTO dbo.orders (id) VALUES (1)',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(
          value.resources.map((r) => r.normalizedName),
          contains('dbo.orders'),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify MERGE', () {
      final result = classifier.classify(
        'MERGE dbo.target AS t USING dbo.source AS s ON t.id = s.id '
        'WHEN MATCHED THEN UPDATE SET t.v = s.v',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        expect(
          value.resources.map((r) => r.normalizedName),
          contains('dbo.target'),
        );
      }, (_) => fail('Expected success'));
    });

    test('should classify UPDATE with FROM using joined tables', () {
      final result = classifier.classify(
        'UPDATE u SET name = 1 FROM dbo.users u INNER JOIN dbo.roles r ON u.role_id = r.id',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.operation, equals(SqlOperation.update));
        final names = value.resources.map((r) => r.normalizedName).toSet();
        expect(names, containsAll(['dbo.users', 'dbo.roles']));
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

    test('should fail on empty SQL', () {
      expect(classifier.classify('').isError(), isTrue);
      expect(classifier.classify('   ').isError(), isTrue);
    });

    test('should fail when comments leave nothing executable', () {
      expect(classifier.classify('-- only a comment').isError(), isTrue);
    });

    test('should fail on unsupported statement type', () {
      expect(
        classifier.classify('CREATE TABLE dbo.t (id int)').isError(),
        isTrue,
      );
    });

    test('should fail when target resources cannot be resolved', () {
      expect(classifier.classify('SELECT * FROM').isError(), isTrue);
    });

    test('should strip block comments before classification', () {
      final result = classifier.classify(
        '/* head */ select * from dbo.users /* tail */',
      );
      expect(result.isSuccess(), isTrue);
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

    test('should read bracket-quoted identifiers', () {
      final result = classifier.classify('SELECT * FROM [dbo].[users]');
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.resources.first.normalizedName, equals('dbo.users'));
      }, (_) => fail('Expected success'));
    });

    test('should parse multiple comma-separated CTEs', () {
      final result = classifier.classify(
        'WITH a AS (SELECT * FROM dbo.t1), b AS (SELECT * FROM dbo.t2) '
        'SELECT * FROM a INNER JOIN b ON 1=1',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        final names = value.resources.map((r) => r.normalizedName).toSet();
        expect(names, containsAll(['dbo.t1', 'dbo.t2']));
      }, (_) => fail('Expected success'));
    });

    test('should tolerate incomplete CTE parentheses and still classify', () {
      final result = classifier.classify(
        'WITH c AS (SELECT * FROM dbo.t',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(value.resources, isNotEmpty);
      }, (_) => fail('Expected success'));
    });

    test('should fail on unclosed bracket identifier', () {
      expect(
        classifier.classify('SELECT * FROM [dbo.users').isError(),
        isTrue,
      );
    });

    test('should fail on unclosed double-quoted identifier', () {
      expect(
        classifier.classify('SELECT * FROM "dbo').isError(),
        isTrue,
      );
    });

    test('should fail on unclosed backtick-quoted identifier', () {
      expect(
        classifier.classify('SELECT * FROM `dbo').isError(),
        isTrue,
      );
    });

    test(
      'should handle CTE column list with unclosed parenthesis',
      () {
        final result = classifier.classify(
          'WITH cols ( SELECT * FROM dbo.t WHERE 1 = 0',
        );
        expect(result.isSuccess(), isTrue);
        result.fold((value) {
          expect(
            value.resources.map((r) => r.normalizedName),
            contains('dbo.t'),
          );
        }, (_) => fail('Expected success'));
      },
    );

    test(
      'should handle CTE with closed column list before AS body',
      () {
        final result = classifier.classify(
          'WITH c (n) AS (SELECT * FROM dbo.t) SELECT * FROM c',
        );
        expect(result.isSuccess(), isTrue);
        result.fold((value) {
          expect(
            value.resources.map((r) => r.normalizedName),
            contains('dbo.t'),
          );
        }, (_) => fail('Expected success'));
      },
    );

    test('should read double-quoted qualified identifiers in FROM', () {
      final result = classifier.classify(
        'SELECT * FROM "dbo"."users"',
      );
      expect(result.isSuccess(), isTrue);
      result.fold((value) {
        expect(
          value.resources.map((r) => r.normalizedName),
          contains('dbo.users'),
        );
      }, (_) => fail('Expected success'));
    });

    test(
      'should classify CTE body that uses bracket-quoted tables',
      () {
        final result = classifier.classify(
          'WITH c AS (SELECT * FROM [dbo].[t]) SELECT * FROM c',
        );
        expect(result.isSuccess(), isTrue);
        result.fold((value) {
          expect(
            value.resources.map((r) => r.normalizedName),
            contains('dbo.t'),
          );
        }, (_) => fail('Expected success'));
      },
    );

    test(
      'findSqlKeyword returns -1 when only a substring matches without boundaries',
      () {
        expect(findSqlKeyword('ba', 'a', 0), equals(-1));
      },
    );
  });
}
