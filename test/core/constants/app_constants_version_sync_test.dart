import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_constants.dart';

void main() {
  test('AppConstants.appVersion matches version declared in pubspec.yaml', () {
    // Reads the pubspec.yaml from the repo root to guard against the generated
    // app_version.g.dart being run stale (out of sync with the pubspec version).
    // If this test fails, re-run `dart run installer/update_version.py` or the
    // equivalent version-bump tooling to regenerate app_version.g.dart.
    final pubspecFile = File('pubspec.yaml');
    expect(pubspecFile.existsSync(), isTrue, reason: 'pubspec.yaml not found at expected path');

    final lines = pubspecFile.readAsLinesSync();
    final versionLine = lines.firstWhere(
      (line) => line.startsWith('version:'),
      orElse: () => '',
    );
    expect(versionLine, isNotEmpty, reason: 'version: key not found in pubspec.yaml');

    final pubspecVersion = versionLine.replaceFirst('version:', '').trim();
    expect(
      AppConstants.appVersion,
      pubspecVersion,
      reason:
          'AppConstants.appVersion ("${AppConstants.appVersion}") does not match '
          'pubspec.yaml version ("$pubspecVersion"). '
          'Re-run the version bump script to regenerate app_version.g.dart.',
    );
  });
}
