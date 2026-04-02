import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/sql_dangerous_pattern_scan.dart';

void main() {
  group('sqlContainsTopLevelDangerousPatterns', () {
    test(
      'should return false when dangerous tokens appear only inside string',
      () {
        expect(
          sqlContainsTopLevelDangerousPatterns(
            "SELECT 1 WHERE x = ';DROP TABLE t'",
          ),
          isFalse,
        );
        expect(
          sqlContainsTopLevelDangerousPatterns(
            "SELECT 1 WHERE x = '-- not a comment'",
          ),
          isFalse,
        );
      },
    );

    test('should return true for top-level line comment', () {
      expect(
        sqlContainsTopLevelDangerousPatterns('SELECT 1 -- hack'),
        isTrue,
      );
    });

    test('should return true for top-level block comment start', () {
      expect(
        sqlContainsTopLevelDangerousPatterns('SELECT 1 /* hack */'),
        isTrue,
      );
    });

    test('should return true when second statement is dangerous', () {
      expect(
        sqlContainsTopLevelDangerousPatterns('SELECT 1; DROP TABLE t'),
        isTrue,
      );
    });
  });
}
