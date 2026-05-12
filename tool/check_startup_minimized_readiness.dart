import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

const _runKeyPath = r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run';
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

  final registryValue = await _readStartupRegistryValue();
  checks.add(
    registryValue == null
        ? const _CheckResult.fail('Windows startup registry', 'Startup entry was not found.')
        : _CheckResult.pass('Windows startup registry', registryValue),
  );
  checks.add(
    registryValue?.contains(AppStrings.singleInstanceArgAutostart) ?? false
        ? const _CheckResult.pass('Autostart argument', AppStrings.singleInstanceArgAutostart)
        : const _CheckResult.fail(
            'Autostart argument',
            'Startup entry must include ${AppStrings.singleInstanceArgAutostart}.',
          ),
  );

  _printResults(checks);
  _printManualChecklist();

  if (checks.any((check) => !check.passed)) {
    exitCode = 1;
  }
}

String _settingsFilePath(List<String> args) {
  final explicitPathIndex = args.indexOf('--settings');
  if (explicitPathIndex >= 0 && explicitPathIndex + 1 < args.length) {
    return args[explicitPathIndex + 1];
  }

  final programData =
      Platform.environment['ProgramData'] ?? Platform.environment['ALLUSERSPROFILE'] ?? r'C:\ProgramData';
  return p.join(programData, GlobalStoragePathResolver.defaultAppFolderName, 'settings.json');
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

Future<String?> _readStartupRegistryValue() async {
  final result = await Process.run('reg', <String>[
    'query',
    _runKeyPath,
    '/v',
    _runValueName,
  ]);
  if (result.exitCode != 0) {
    return null;
  }

  final output = '${result.stdout}\n${result.stderr}';
  for (final line in output.split(RegExp(r'\r?\n'))) {
    if (line.contains(_runValueName) && line.contains('REG_')) {
      return line.trim();
    }
  }
  return output.trim().isEmpty ? null : output.trim();
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
