import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/core/constants/app_constants.dart';

/// Mantém [AppConstants.appVersion] (gerado em
/// `lib/core/constants/app_version.g.dart`) alinhado com o `version` do
/// `pubspec.yaml`. Se este teste falhar, rode:
///
///   python installer/update_version.py
///
/// para regenerar o arquivo.
void main() {
  group('AppConstants.appVersion consistency', () {
    test('AppConstants.appVersion deve refletir pubspec.yaml version', () {
      final pubspecPath = path.join(Directory.current.path, 'pubspec.yaml');
      final pubspec = File(pubspecPath);
      expect(pubspec.existsSync(), isTrue, reason: 'pubspec.yaml should exist');

      final lines = pubspec.readAsLinesSync();
      final versionLine = lines.firstWhere(
        (line) => RegExp(r'^version:\s*').hasMatch(line),
        orElse: () => '',
      );
      expect(
        versionLine.isNotEmpty,
        isTrue,
        reason: 'pubspec.yaml deve declarar `version:`',
      );

      final declared = versionLine
          .replaceFirst(RegExp(r'^version:\s*'), '')
          .replaceAll(RegExp('["\']'), '')
          .split('#')
          .first
          .trim();

      expect(
        AppConstants.appVersion,
        equals(declared),
        reason:
            'AppConstants.appVersion ($appVersionForReason) está fora de sincronia com pubspec.yaml ($declared). '
            'Rode `python installer/update_version.py` para regenerar lib/core/constants/app_version.g.dart.',
      );
    });
  });
}

String get appVersionForReason => AppConstants.appVersion;
