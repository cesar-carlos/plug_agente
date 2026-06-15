import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('startup minimized readiness tool', () {
    test('checks both user and machine startup registry scopes', () {
      final script = File('tool/dev/check_startup_minimized_readiness.dart').readAsStringSync();
      final registryHelper = File('lib/infrastructure/services/startup_registry_entry.dart').readAsStringSync();

      expect(script, contains('StartupRegistryScope.values'));
      expect(registryHelper, contains(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'));
      expect(registryHelper, contains(r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run'));
    });

    test('supports expected executable path validation', () {
      final script = File('tool/dev/check_startup_minimized_readiness.dart').readAsStringSync();

      expect(script, contains('--expected-exe'));
      expect(script, contains('matchesExpectedExecutable'));
    });
  });
}
