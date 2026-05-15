import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';

void main() {
  group('AppVersionComparator', () {
    test('orders semantic version and build metadata', () {
      expect(AppVersionComparator.compare('1.2.4+1', '1.2.3+99'), greaterThan(0));
      expect(AppVersionComparator.compare('1.2.3+2', '1.2.3+1'), greaterThan(0));
      expect(AppVersionComparator.compare('1.2.3+1', '1.2.3+1'), 0);
      expect(AppVersionComparator.compare('1.2.3', '1.2.3+1'), lessThan(0));
    });

    test('rejects malformed versions', () {
      expect(
        () => AppVersionComparator.compare('1.2', '1.2.3+1'),
        throwsFormatException,
      );
      expect(
        () => AppVersionComparator.compare('1.2.3+beta', '1.2.3+1'),
        throwsFormatException,
      );
    });
  });
}
