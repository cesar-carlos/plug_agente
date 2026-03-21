import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/summarize_lcov.dart';

void main() {
  group('parseLcovSummaries', () {
    test('should parse SF/LF/LH blocks', () {
      const raw = '''
SF:lib/a.dart
DA:1,1
LF:10
LH:7
end_of_record
SF:lib/b.dart
LF:5
LH:0
end_of_record
''';
      final list = parseLcovSummaries(raw);
      check(list.length).equals(2);
      check(list[0].path).contains('a.dart');
      check(list[0].linesFound).equals(10);
      check(list[0].linesHit).equals(7);
      check(list[1].linesHit).equals(0);
    });
  });

  group('hitRatio', () {
    test('should return 1 when linesFound is zero', () {
      check(
        hitRatio((path: 'x', linesFound: 0, linesHit: 0)),
      ).equals(1);
    });
  });
}
