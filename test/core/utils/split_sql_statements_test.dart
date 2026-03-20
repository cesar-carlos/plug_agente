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
}
