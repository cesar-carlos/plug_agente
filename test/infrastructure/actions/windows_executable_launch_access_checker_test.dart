import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';

void main() {
  group('WindowsExecutableLaunchAccessChecker', () {
    test('should require launch access only for exe and com extensions', () {
      expect(
        WindowsExecutableLaunchAccessChecker.extensionRequiresLaunchAccess('.exe'),
        isTrue,
      );
      expect(
        WindowsExecutableLaunchAccessChecker.extensionRequiresLaunchAccess('.com'),
        isTrue,
      );
      expect(
        WindowsExecutableLaunchAccessChecker.extensionRequiresLaunchAccess('.bat'),
        isFalse,
      );
    });

    test('should allow launch preflight for system cmd on Windows', () {
      if (!Platform.isWindows) {
        return;
      }

      final failure = WindowsExecutableLaunchAccessChecker.validateLaunchAccess(
        actionId: 'action-1',
        field: 'executablePath',
        path: r'C:\Windows\System32\cmd.exe',
        phase: 'execution_preflight',
      );

      expect(failure, isNull);
    });
  });
}
