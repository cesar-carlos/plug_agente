import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';

void main() {
  group('truncateSqlResultRows', () {
    test('should return same list when within maxRows', () {
      final rows = [
        {'a': 1},
        {'a': 2},
      ];
      final out = truncateSqlResultRows(rows, 10);
      expect(out, same(rows));
    });

    test('should truncate when rows exceed maxRows', () {
      final rows = [
        {'a': 1},
        {'a': 2},
        {'a': 3},
      ];
      final out = truncateSqlResultRows(rows, 2);
      expect(out, hasLength(2));
      expect(out[0]['a'], 1);
      expect(out[1]['a'], 2);
    });

    test('should not truncate when maxRows is below 1', () {
      final rows = [
        {'a': 1},
      ];
      final out = truncateSqlResultRows(rows, 0);
      expect(out, same(rows));
    });
  });
}
