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
