import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/windows_environment_string_expander.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';

void main() {
  group('expandWindowsEnvironmentStrings', () {
    test('should leave values without percent tokens unchanged', () {
      const value = r'C:\Program Files\PlugAgente\plug_agente.exe';
      check(expandWindowsEnvironmentStrings(value)).equals(value);
    });

    test('should expand percent tokens through the provided expander', () {
      final expanded = expandWindowsEnvironmentStrings(
        r'%ProgramFiles%\PlugAgente\plug_agente.exe',
        expander: (value) => value.replaceAll('%ProgramFiles%', r'C:\Program Files'),
      );

      check(expanded).equals(r'C:\Program Files\PlugAgente\plug_agente.exe');
    });
  });

  group('Win32StartupRunValueRegistryReader environment expansion hook', () {
    test('should accept an injectable environment expander', () {
      final reader = Win32StartupRunValueRegistryReader(
        environmentExpander: (value) => value.replaceAll('%ProgramFiles%', r'C:\Program Files'),
      );
      check(reader).isA<IStartupRunValueRegistryReader>();
    });
  });
}
