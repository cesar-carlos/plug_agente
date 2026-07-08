import 'package:plug_agente/core/utils/launch_args.dart';

enum StartupRegistryScope {
  currentUser,
  localMachine,
  localMachineWow6432;

  String get runKeyPath => switch (this) {
    StartupRegistryScope.currentUser => r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
    StartupRegistryScope.localMachine => r'HKLM\Software\Microsoft\Windows\CurrentVersion\Run',
    StartupRegistryScope.localMachineWow6432 => r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
  };

  String get powershellLiteralPath => switch (this) {
    StartupRegistryScope.currentUser => r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    StartupRegistryScope.localMachine => r'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    StartupRegistryScope.localMachineWow6432 => r'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
  };

  bool get requiresElevation =>
      this == StartupRegistryScope.localMachine || this == StartupRegistryScope.localMachineWow6432;

  bool get isMachineScope => requiresElevation;

  String get label => switch (this) {
    StartupRegistryScope.currentUser => 'HKCU',
    StartupRegistryScope.localMachine => 'HKLM',
    StartupRegistryScope.localMachineWow6432 => 'HKLM_WOW64',
  };

  static Iterable<StartupRegistryScope> get machineScopes => [
    StartupRegistryScope.localMachine,
    StartupRegistryScope.localMachineWow6432,
  ];
}

class StartupRegistryEntry {
  const StartupRegistryEntry({
    required this.scope,
    required this.valueName,
    required this.rawValue,
    required this.executablePath,
    required this.arguments,
  });

  final StartupRegistryScope scope;
  final String valueName;
  final String rawValue;
  final String executablePath;
  final String arguments;

  bool get hasAutostartArgument => containsAutostartLaunchToken(rawValue);

  bool matchesExpectedExecutable(String expectedExecutablePath) {
    return _normalizeExecutablePath(executablePath) == _normalizeExecutablePath(expectedExecutablePath);
  }

  bool isHealthyFor(String expectedExecutablePath) {
    return hasAutostartArgument && matchesExpectedExecutable(expectedExecutablePath);
  }

  static StartupRegistryEntry? fromRawValue({
    required StartupRegistryScope scope,
    required String valueName,
    required String rawValue,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final executablePath = _parseExecutablePath(trimmed);
    if (executablePath == null || executablePath.isEmpty) {
      return null;
    }

    return StartupRegistryEntry(
      scope: scope,
      valueName: valueName,
      rawValue: trimmed,
      executablePath: executablePath,
      arguments: _parseArguments(trimmed),
    );
  }

  static StartupRegistryEntry? tryParse({
    required StartupRegistryScope scope,
    required String valueName,
    required String output,
  }) {
    final valuePattern = RegExp(
      '${RegExp.escape(valueName)}\\s+REG_\\w+\\s+(.+)\$',
      caseSensitive: false,
    );

    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = valuePattern.firstMatch(line.trim());
      if (match == null) {
        continue;
      }

      final rawValue = match.group(1)?.trim();
      if (rawValue == null || rawValue.isEmpty) {
        return null;
      }

      return fromRawValue(
        scope: scope,
        valueName: valueName,
        rawValue: rawValue,
      );
    }

    return null;
  }

  static String? _parseExecutablePath(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('"')) {
      final closingQuoteIndex = trimmed.indexOf('"', 1);
      if (closingQuoteIndex > 1) {
        return trimmed.substring(1, closingQuoteIndex);
      }
    }

    final whitespaceMatch = RegExp(r'\s').firstMatch(trimmed);
    if (whitespaceMatch == null) {
      return trimmed;
    }
    return trimmed.substring(0, whitespaceMatch.start);
  }

  static String _parseArguments(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if (trimmed.startsWith('"')) {
      final closingQuoteIndex = trimmed.indexOf('"', 1);
      if (closingQuoteIndex > 0 && closingQuoteIndex + 1 < trimmed.length) {
        return trimmed.substring(closingQuoteIndex + 1).trim();
      }
      return '';
    }

    final whitespaceMatch = RegExp(r'\s').firstMatch(trimmed);
    if (whitespaceMatch == null) {
      return '';
    }
    return trimmed.substring(whitespaceMatch.end).trim();
  }
}

String normalizeStartupExecutablePath(String value) {
  return _normalizeExecutablePath(value);
}

String _normalizeExecutablePath(String value) {
  var normalized = value.trim();
  if (normalized.startsWith('"') && normalized.endsWith('"') && normalized.length > 1) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  if (normalized.startsWith(r'\\?\')) {
    normalized = normalized.substring(4);
  }
  return normalized.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();
}
