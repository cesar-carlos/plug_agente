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

    test('strips pre-release label before comparing', () {
      // "1.2.3-beta.1" is treated as "1.2.3" (build = 0).
      expect(AppVersionComparator.compare('1.2.3-beta.1', '1.2.2'), greaterThan(0));
      expect(AppVersionComparator.compare('1.2.3-beta.1', '1.2.3'), 0);
      expect(AppVersionComparator.compare('1.2.3-beta.1', '1.2.4'), lessThan(0));
    });

    test('strips pre-release label while preserving build metadata', () {
      // "1.2.3-rc.1+5" → "1.2.3+5"; build 5 > build 0.
      expect(AppVersionComparator.compare('1.2.3-rc.1+5', '1.2.3'), greaterThan(0));
    });

    test('isRemoteVersionNewer returns false when remote is pre-release of same base', () {
      // Appcast accidentally ships "1.2.3-beta.1"; treated equal to current "1.2.3".
      expect(
        AppVersionComparator.isRemoteVersionNewer(
          remoteVersion: '1.2.3-beta.1',
          currentVersion: '1.2.3',
        ),
        isFalse,
      );
    });
  });
}
