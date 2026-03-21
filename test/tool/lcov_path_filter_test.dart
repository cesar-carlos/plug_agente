import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/lcov_path_filter.dart';

void main() {
  group('filterLcovByPathPrefixes', () {
    test('should keep only blocks whose SF matches a prefix', () {
      const raw = '''
SF:lib/application/rpc/foo.dart
DA:1,1
end_of_record
SF:lib/other.dart
DA:1,0
end_of_record
SF:lib/application/rpc/bar.dart
DA:2,1
end_of_record
''';
      final out = filterLcovByPathPrefixes(
        raw,
        <String>['lib/application/rpc/'],
      );
      check(out.contains('foo.dart')).isTrue();
      check(out.contains('bar.dart')).isTrue();
      check(out.contains('other.dart')).isFalse();
      check(RegExp('end_of_record').allMatches(out).length).equals(2);
    });

    test('should normalize backslashes before matching', () {
      const raw = r'''
SF:lib\infrastructure\external_services\odbc_x.dart
DA:1,1
end_of_record
''';
      final out = filterLcovByPathPrefixes(
        raw,
        <String>['lib/infrastructure/external_services/odbc_'],
      );
      check(out.contains('odbc_x.dart')).isTrue();
    });

    test('should return empty string when no block matches', () {
      const raw = '''
SF:lib/unrelated/a.dart
DA:1,1
end_of_record
''';
      final out = filterLcovByPathPrefixes(raw, <String>['lib/application/rpc/']);
      check(out.trim().isEmpty).isTrue();
    });

    test('should return full content when prefix list is empty', () {
      const raw = 'SF:a.dart\nend_of_record\n';
      check(filterLcovByPathPrefixes(raw, <String>[])).equals(raw);
    });
  });
}
