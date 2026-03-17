import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/utils/launch_args.dart';

void main() {
  group('autostart constant consistency', () {
    test('should match constants/autostart_arg.txt when file exists', () {
      final file = File('constants/autostart_arg.txt');
      if (file.existsSync()) {
        final canonical = file.readAsStringSync().trim();
        expect(
          AppStrings.singleInstanceArgAutostart,
          equals(canonical),
          reason: 'app_strings must match constants/autostart_arg.txt',
        );
      }
    });
  });

  group('isAutostartLaunch', () {
    test('should return true when args contain --autostart', () {
      expect(isAutostartLaunch(['--autostart']), isTrue);
      expect(isAutostartLaunch(['plug_agente.exe', '--autostart']), isTrue);
      expect(
        isAutostartLaunch(['exe', 'plugdb://config', '--autostart']),
        isTrue,
      );
    });

    test('should return false when args do not contain --autostart', () {
      expect(isAutostartLaunch([]), isFalse);
      expect(isAutostartLaunch(['plug_agente.exe']), isFalse);
      expect(isAutostartLaunch(['--verbose', 'plugdb://config']), isFalse);
    });

    test('should not match partial strings', () {
      expect(isAutostartLaunch(['--autostart-extra']), isFalse);
      expect(isAutostartLaunch(['autostart']), isFalse);
    });
  });
}
