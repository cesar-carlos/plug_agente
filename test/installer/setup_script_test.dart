import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('installer setup script', () {
    test('keeps admin as default and allows command-line privilege override', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains('PrivilegesRequired=admin'));
      expect(setupScript, contains('PrivilegesRequiredOverridesAllowed=commandline'));
    });

    test('declares and installs native update helper', () {
      final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
      final helperCmake = File('windows/update_helper/CMakeLists.txt').readAsStringSync();

      expect(windowsCmake, contains('add_subdirectory("update_helper")'));
      expect(helperCmake, contains('add_executable(plug_update_helper'));
      expect(helperCmake, contains('install(TARGETS plug_update_helper'));
    });

    test('installer build preflight requires update helper in bundle', () {
      final buildScript = File('installer/build_installer.py').readAsStringSync();

      expect(buildScript, contains('plug_update_helper.exe'));
      expect(buildScript, contains('helper de update'));
    });
  });
}
