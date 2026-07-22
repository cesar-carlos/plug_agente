import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

class WindowsElevatedRegistryExecutor {
  WindowsElevatedRegistryExecutor({
    ProcessRunner? processRunner,
  }) : _processRunner = processRunner ?? Process.run;

  /// Win32 `ERROR_ACCESS_DENIED`.
  static const int accessDeniedExitCode = 5;

  /// Win32 `ERROR_CANCELLED` (typical UAC decline).
  static const int uacCancelledExitCode = 1223;

  final ProcessRunner _processRunner;

  Future<ProcessResult> deleteRunValue({
    required StartupRegistryScope scope,
    required String valueName,
  }) {
    final escapedName = valueName.replaceAll("'", "''");
    final innerScript =
        '''
\$ErrorActionPreference = 'Stop'
\$keyPath = '${scope.powershellLiteralPath}'
\$valueName = '$escapedName'
if (Get-ItemProperty -LiteralPath \$keyPath -Name \$valueName -ErrorAction SilentlyContinue) {
  Remove-ItemProperty -LiteralPath \$keyPath -Name \$valueName -ErrorAction Stop
}
exit 0
''';
    return runEncodedElevated(innerScript);
  }

  Future<ProcessResult> setRunValue({
    required StartupRegistryScope scope,
    required String valueName,
    required String rawValueData,
  }) {
    final escapedName = valueName.replaceAll("'", "''");
    final escapedValue = rawValueData.replaceAll("'", "''");
    final innerScript =
        '''
\$ErrorActionPreference = 'Stop'
New-ItemProperty -LiteralPath '${scope.powershellLiteralPath}' -Name '$escapedName' -Value '$escapedValue' -PropertyType String -Force | Out-Null
exit 0
''';
    return runEncodedElevated(innerScript);
  }

  Future<ProcessResult> runEncodedElevated(String innerScript) {
    final encoded = base64Encode(encodeUtf16Le(innerScript));
    final launcher =
        '''
\$ErrorActionPreference = "Stop"
try {
  \$p = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-NonInteractive","-EncodedCommand","$encoded") -Verb RunAs -Wait -PassThru
  if (\$null -eq \$p) {
    [Console]::Error.WriteLine("Failed to start elevated PowerShell process.")
    exit 1
  }
  exit \$p.ExitCode
} catch {
  \$native = 0
  try { \$native = [int]\$_.Exception.NativeErrorCode } catch {}
  if (\$native -eq $uacCancelledExitCode) { exit $uacCancelledExitCode }
  if (\$native -eq $accessDeniedExitCode) { exit $accessDeniedExitCode }
  \$message = \$_.Exception.Message
  if (\$message -match 'canceled by the user|cancelled by the user|cancelada pelo usuario') {
    exit $uacCancelledExitCode
  }
  if (\$message -match 'access is denied|acesso negado') {
    exit $accessDeniedExitCode
  }
  [Console]::Error.WriteLine(\$message)
  exit 1
}
''';
    return _processRunner('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      launcher,
    ]);
  }

  static List<int> encodeUtf16Le(String value) {
    final bytes = <int>[];
    for (final codeUnit in value.codeUnits) {
      bytes
        ..add(codeUnit & 0xFF)
        ..add(codeUnit >> 8);
    }
    return bytes;
  }

  static bool isAccessDenied(ProcessResult result) {
    if (result.exitCode == accessDeniedExitCode) {
      return true;
    }
    final output = normalizedProcessOutput(result);
    return output.contains('access is denied') || output.contains('acesso negado');
  }

  static bool isUacCancelled(ProcessResult result) {
    if (result.exitCode == uacCancelledExitCode) {
      return true;
    }
    final output = normalizedProcessOutput(result);
    return output.contains('operation was canceled by the user') ||
        output.contains('operation was cancelled by the user') ||
        output.contains('operacao foi cancelada pelo usuario') ||
        output.contains('a operacao foi cancelada pelo usuario');
  }

  static String normalizedProcessOutput(ProcessResult result) {
    return stripDiacritics('${result.stdout}\n${result.stderr}'.toLowerCase());
  }

  static String stripDiacritics(String value) {
    const replacements = <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(replacements[character] ?? character);
    }
    return buffer.toString();
  }
}
