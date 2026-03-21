import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart';

void main() {
  group('splitSqlStatements', () {
    test('should split two simple SELECT statements', () {
      expect(
        splitSqlStatements('SELECT 1; SELECT 2'),
        ['SELECT 1', 'SELECT 2'],
      );
    });

    test('should not split on semicolon inside single-quoted string', () {
      expect(
        splitSqlStatements("SELECT 'a;b' AS x FROM t"),
        ["SELECT 'a;b' AS x FROM t"],
      );
    });

    test('should not split on semicolon inside double-quoted identifier', () {
      expect(
        splitSqlStatements('SELECT 1 AS "x;y" FROM t'),
        ['SELECT 1 AS "x;y" FROM t'],
      );
    });

    test('should trim and skip empty fragments', () {
      expect(
        splitSqlStatements('  SELECT 1  ;  ; SELECT 2  '),
        ['SELECT 1', 'SELECT 2'],
      );
    });

    test(
      'should preserve bracket-delimited identifiers across semicolon-like',
      () {
        expect(
          splitSqlStatements('SELECT [a;b] FROM t'),
          ['SELECT [a;b] FROM t'],
        );
      },
    );

    test('should split after line comment that contains a semicolon', () {
      expect(
        splitSqlStatements('SELECT 1 -- ; not a splitter\n; SELECT 2'),
        ['SELECT 1 -- ; not a splitter', 'SELECT 2'],
      );
    });

    test('should split when semicolon appears inside block comment only', () {
      expect(
        splitSqlStatements('SELECT 1/*;not split*/; SELECT 2'),
        ['SELECT 1/*;not split*/', 'SELECT 2'],
      );
    });

    test('should handle doubled single-quote escape inside string literal', () {
      expect(
        splitSqlStatements("SELECT 'a'';b' AS x; SELECT 2"),
        ["SELECT 'a'';b' AS x", 'SELECT 2'],
      );
    });

    test(
      'should match multi_result-style probe (two SELECTs separated by ;)',
      () {
        const probe =
            'SELECT id FROM t WHERE id = 1;\n'
            'SELECT COUNT(*) AS row_count FROM t;';
        final parts = splitSqlStatements(probe);
        expect(parts, hasLength(2));
        expect(parts[0], contains('WHERE id = 1'));
        expect(parts[1], contains('COUNT(*)'));
      },
    );
  });

  group('splitSqlStatements (documented limits)', () {
    test('should not split on SQL Server GO (treated as plain text)', () {
      expect(
        splitSqlStatements('SELECT 1\nGO\nSELECT 2'),
        ['SELECT 1\nGO\nSELECT 2'],
      );
    });

    test(
      'should mis-split when semicolon is inside PostgreSQL dollar quotes',
      () {
        expect(
          splitSqlStatements(r'SELECT $$a;b$$; SELECT 2'),
          [r'SELECT $$a', r'b$$', 'SELECT 2'],
        );
      },
    );

    test(
      'should mis-split when semicolon is inside MySQL-style backtick id',
      () {
        expect(
          splitSqlStatements('SELECT `a;b` FROM t; SELECT 2'),
          ['SELECT `a', 'b` FROM t', 'SELECT 2'],
        );
      },
    );
  });

  group('sqlHasMultipleTopLevelStatements', () {
    test('should be false for single statement with semicolon in string', () {
      expect(sqlHasMultipleTopLevelStatements("SELECT ';' AS x"), isFalse);
    });

    test('should be true for two top-level statements', () {
      expect(sqlHasMultipleTopLevelStatements('SELECT 1; SELECT 2'), isTrue);
    });

    test('should agree with splitSqlStatements segment count', () {
      const cases = <String>[
        'SELECT 1; SELECT 2',
        "SELECT 'a;b' AS x FROM t",
        'SELECT 1 AS "x;y" FROM t',
        '  SELECT 1  ;  ; SELECT 2  ',
        'SELECT [a;b] FROM t',
        "SELECT ';' AS x",
      ];
      for (final sql in cases) {
        expect(
          sqlHasMultipleTopLevelStatements(sql),
          splitSqlStatements(sql).length > 1,
          reason: sql,
        );
      }
    });
  });

  group('sqlStatementsForClientTokenAuthorization', () {
    test('should match splitSqlStatements when non-empty', () {
      expect(
        sqlStatementsForClientTokenAuthorization('SELECT 1; SELECT 2'),
        splitSqlStatements('SELECT 1; SELECT 2'),
      );
      expect(
        sqlStatementsForClientTokenAuthorization('SELECT 1'),
        splitSqlStatements('SELECT 1'),
      );
    });

    test('should fall back to original SQL when split yields no fragments', () {
      expect(sqlStatementsForClientTokenAuthorization(';;;'), [';;;']);
    });
  });
}
