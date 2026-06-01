import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';

void main() {
  group('StartupRegistryEntry', () {
    test('should parse reg query output and validate expected executable plus autostart token', () {
      const output = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
    Plug Agente    REG_SZ    "C:\Program Files\PlugAgente\plug_agente.exe" "--autostart"
''';

      final entry = StartupRegistryEntry.tryParse(
        scope: StartupRegistryScope.currentUser,
        valueName: 'Plug Agente',
        output: output,
      );

      check(entry).isNotNull();
      check(entry!.scope).equals(StartupRegistryScope.currentUser);
      check(entry.executablePath).equals(r'C:\Program Files\PlugAgente\plug_agente.exe');
      check(entry.hasAutostartArgument).equals(true);
      check(entry.matchesExpectedExecutable('C:/Program Files/PlugAgente/plug_agente.exe')).equals(true);
    });

    test('should reject stale executable paths', () {
      const output = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
    Plug Agente    REG_SZ    "C:\Old\PlugAgente\plug_agente.exe" "--autostart"
''';

      final entry = StartupRegistryEntry.tryParse(
        scope: StartupRegistryScope.currentUser,
        valueName: 'Plug Agente',
        output: output,
      );

      check(entry).isNotNull();
      check(entry!.hasAutostartArgument).equals(true);
      check(entry.matchesExpectedExecutable(r'C:\Program Files\PlugAgente\plug_agente.exe')).equals(false);
    });

    test('should reject partial autostart token', () {
      const output = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
    Plug Agente    REG_SZ    "C:\Program Files\PlugAgente\plug_agente.exe" "--autostart-extra"
''';

      final entry = StartupRegistryEntry.tryParse(
        scope: StartupRegistryScope.currentUser,
        valueName: 'Plug Agente',
        output: output,
      );

      check(entry).isNotNull();
      check(entry!.hasAutostartArgument).equals(false);
    });
  });
}
