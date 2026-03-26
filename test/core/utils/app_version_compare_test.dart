import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/app_version_compare.dart';

void main() {
  group('compareReleaseVersions', () {
    test('orders by major.minor.patch then build', () {
      expect(compareReleaseVersions('1.0.0+1', '1.0.0+2'), lessThan(0));
      expect(compareReleaseVersions('1.0.1', '1.0.0+99'), greaterThan(0));
      expect(compareReleaseVersions('1.1.2+18', '1.1.1+99'), greaterThan(0));
    });

    test('treats missing build as zero', () {
      expect(compareReleaseVersions('1.0.0', '1.0.0+0'), 0);
    });
  });
}
