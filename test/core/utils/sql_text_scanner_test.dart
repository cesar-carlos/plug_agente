import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/sql_text_scanner.dart';

void main() {
  group('scanSqlText', () {
    test('treats dashes and semicolons inside strings as literals', () {
      const sql = "SELECT '-- keep; DROP' FROM t";
      final code = StringBuffer();
      final literals = <String>[];
      scanSqlText(
        sql,
        onCode: (start, end) => code.write(sql.substring(start, end)),
        onLiteral: (start, end) => literals.add(sql.substring(start, end)),
        onComment: (_, _, {required isBlock}) => fail('unexpected comment'),
      );

      expect(code.toString(), contains('SELECT'));
      expect(code.toString(), isNot(contains('--')));
      expect(code.toString(), isNot(contains(';')));
      expect(literals, ["'-- keep; DROP'"]);
    });
  });
}
