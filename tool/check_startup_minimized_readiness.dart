import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';

const _runValueName = 'Plug Agente';

Future<void> main(List<String> args) async {
  final checks = <_CheckResult>[];

  if (!Platform.isWindows) {
    checks.add(
      const _CheckResult.fail(
        'Windows platform',
        'This startup readiness check only applies to Windows.',
      ),
    );
    _printResults(checks);
    exitCode = 1;
    return;
  }

  final settingsFile = File(_settingsFilePath(args));
  checks.add(
    settingsFile.existsSync()
        ? _CheckResult.pass('Global settings file', settingsFile.path)
        : _CheckResult.fail('Global settings file', '${settingsFile.path} was not found.'),
  );

  final settings = settingsFile.existsSync() ? _readSettings(settingsFile) : <String, Object?>{};
  checks
    ..add(_expectBool(settings, AppSettingsKeys.startWithWindows, true))
    ..add(_expectBool(settings, AppSettingsKeys.startMinimized, true))
    ..add(_expectBool(settings, AppSettingsKeys.minimizeToTray, true));

  final registryEntries = await _readStartupRegistryEntries();
  checks.add(
    registryEntries.isEmpty
        ? const _CheckResult.fail('Windows startup registry', 'Startup entry was not found.')
        : _CheckResult.pass(
            'Windows startup registry',
            registryEntries.map((entry) => '${entry.scope.label}: ${entry.detail}').join(' | '),
          ),
  );
  checks.add(
    registryEntries.length <= 1
        ? _CheckResult.pass('Startup registry scope count', '${registryEntries.length}')
        : _CheckResult.fail(
            'Startup registry scope count',
            'Expected one startup entry but found ${registryEntries.length}: '
                '${registryEntries.map((entry) => entry.scope.label).join(', ')}.',
          ),
  );
  checks.add(
    registryEntries.any((registryEntry) => registryEntry.entry?.hasAutostartArgument ?? false)
        ? const _CheckResult.pass('Autostart argument', AppStrings.singleInstanceArgAutostart)
        : const _CheckResult.fail(
            'Autostart argument',
            'Startup entry must include ${AppStrings.singleInstanceArgAutostart}.',
          ),
  );

  final expectedExecutablePath = _argValue(args, '--expected-exe');
  if (expectedExecutablePath != null) {
    final matchingEntries = registryEntries
        .where((registryEntry) => registryEntry.entry?.matchesExpectedExecutable(expectedExecutablePath) ?? false)
        .toList();
    checks.add(
      matchingEntries.length == 1 && registryEntries.length == 1
          ? _CheckResult.pass('Startup executable path', expectedExecutablePath)
          : _CheckResult.fail(
              'Startup executable path',
              'Expected exactly one startup entry pointing to $expectedExecutablePath.',
            ),
    );
  }

  _printResults(checks);
  _printManualChecklist();

  if (checks.any((check) => !check.passed)) {
    exitCode = 1;
  }
}

String _settingsFilePath(List<String> args) {
  final explicitPath = _argValue(args, '--settings');
  if (explicitPath != null) {
    return explicitPath;
  }

  final programData =
      Platform.environment['ProgramData'] ?? Platform.environment['ALLUSERSPROFILE'] ?? r'C:\ProgramData';
  return p.join(programData, GlobalStoragePathResolver.defaultAppFolderName, 'settings.json');
}

String? _argValue(List<String> args, String name) {
  final explicitPathIndex = args.indexOf(name);
  if (explicitPathIndex >= 0 && explicitPathIndex + 1 < args.length) {
    return args[explicitPathIndex + 1];
  }
  return null;
}

Map<String, Object?> _readSettings(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } on Object catch (error) {
    return <String, Object?>{
      '__read_error__': error.toString(),
    };
  }
  return <String, Object?>{};
}

_CheckResult _expectBool(Map<String, Object?> settings, String key, bool expected) {
  if (settings.containsKey('__read_error__')) {
    return _CheckResult.fail(key, 'Could not read settings: ${settings['__read_error__']}');
  }

  final value = settings[key];
  return value == expected
      ? _CheckResult.pass(key, '$value')
      : _CheckResult.fail(key, 'Expected $expected but found ${value ?? 'missing'}.');
}

Future<List<_StartupRegistryRead>> _readStartupRegistryEntries() async {
  final entries = <_StartupRegistryRead>[];
  for (final scope in StartupRegistryScope.values) {
    final result = await Process.run('reg', <String>[
      'query',
      scope.runKeyPath,
      '/v',
      _runValueName,
    ]);
    if (result.exitCode != 0) {
      continue;
    }

    final output = '${result.stdout}\n${result.stderr}';
    entries.add(
      _StartupRegistryRead(
        scope: scope,
        output: output,
        entry: StartupRegistryEntry.tryParse(
          scope: scope,
          valueName: _runValueName,
          output: output,
        ),
      ),
    );
  }
  return entries;
}

void _printResults(List<_CheckResult> checks) {
  stdout.writeln('Startup minimized readiness');
  for (final check in checks) {
    final marker = check.passed ? '[OK]' : '[FAIL]';
    stdout.writeln('$marker ${check.name}: ${check.detail}');
  }
}

void _printManualChecklist() {
  stdout
    ..writeln()
    ..writeln('Manual E2E checklist')
    ..writeln('1. Install or run the Release build that contains the startup fix.')
    ..writeln('2. In Settings > Preferences, enable Start with Windows, Start minimized, and Minimize to tray.')
    ..writeln('3. Run this script and confirm every readiness check is OK.')
    ..writeln('4. Sign out and sign in again, or restart Windows.')
    ..writeln('5. Confirm Plug Database appears in the tray without flashing or opening the main window.')
    ..writeln('6. Open it from the tray menu and confirm the window restores normally.');
}

class _CheckResult {
  const _CheckResult.pass(this.name, this.detail) : passed = true;
  const _CheckResult.fail(this.name, this.detail) : passed = false;

  final bool passed;
  final String name;
  final String detail;
}

class _StartupRegistryRead {
  const _StartupRegistryRead({
    required this.scope,
    required this.output,
    required this.entry,
  });

  final StartupRegistryScope scope;
  final String output;
  final StartupRegistryEntry? entry;

  String get detail => entry?.rawValue ?? output.trim();
}
