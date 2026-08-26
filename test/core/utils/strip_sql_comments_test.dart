import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/strip_sql_comments.dart';

void main() {
  group('stripTopLevelSqlComments', () {
    test('should replace line comments with a space', () {
      final stripped = stripTopLevelSqlComments('SELECT id -- hidden\nFROM users');
      expect(stripped, isNot(contains('-- hidden')));
      expect(stripped, contains('SELECT id'));
      expect(stripped, contains('FROM users'));
    });

    test('should replace block comments with a space', () {
      final stripped = stripTopLevelSqlComments('SELECT /* note */ id FROM users');
      expect(stripped, isNot(contains('/* note */')));
      expect(stripped.contains('SELECT'), isTrue);
      expect(stripped.contains('id FROM users'), isTrue);
    });

    test('should not glue tokens around a block comment', () {
      expect(
        stripTopLevelSqlComments('SELECT/*x*/FROM users').trim(),
        'SELECT FROM users',
      );
    });

    test('should keep comment markers inside string literals', () {
      expect(
        stripTopLevelSqlComments("SELECT '-- keep', '/* keep */' FROM t"),
        "SELECT '-- keep', '/* keep */' FROM t",
      );
    });

    test('should keep comment markers inside bracket identifiers', () {
      expect(
        stripTopLevelSqlComments('SELECT [--not-comment] FROM t'),
        'SELECT [--not-comment] FROM t',
      );
    });

    test('should strip a leading documentation comment', () {
      final stripped = stripTopLevelSqlComments('/* CONTA RECEBER */\nSELECT 1');
      expect(stripped.trim().toLowerCase().startsWith('select'), isTrue);
    });

    test('should consume an unclosed block comment', () {
      expect(
        stripTopLevelSqlComments('SELECT 1 /* unclosed').trim(),
        'SELECT 1',
      );
    });

    test('should strip a line comment at end of file without newline', () {
      expect(
        stripTopLevelSqlComments('SELECT 1 -- trailing').trim(),
        'SELECT 1',
      );
    });
  });
}
