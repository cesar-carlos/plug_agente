import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/prepared_sql.dart';

void main() {
  group('PreparedSql', () {
    test('keeps raw SQL and strips comments for analysis', () {
      const raw = 'SELECT 1 -- note';
      final prepared = PreparedSql.parse(raw);

      expect(prepared.raw, raw);
      expect(prepared.trimmed, raw);
      expect(prepared.stripped, isNot(contains('--')));
      expect(prepared.stripped, contains('SELECT 1'));
      expect(prepared.hasMultipleStatements, isFalse);
      expect(prepared.fingerprint, PreparedSql.fingerprintFor('SELECT 1'));
    });

    test('detects multiple top-level statements on the original text', () {
      final prepared = PreparedSql.parse('SELECT 1; DROP TABLE t');
      expect(prepared.hasMultipleStatements, isTrue);
    });

    test('does not treat semicolon inside a string as a second statement', () {
      final prepared = PreparedSql.parse("SELECT '-- keep; DROP' FROM t");
      expect(prepared.hasMultipleStatements, isFalse);
    });
  });
}
