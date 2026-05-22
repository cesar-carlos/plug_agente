final class PowerShellInlineCommand {
  const PowerShellInlineCommand({
    required this.executable,
    required this.command,
  });

  final String executable;
  final String command;
}

abstract final class PowerShellCommandLine {
  static const String windowsPowerShellExecutable = 'powershell.exe';
  static const String powerShell7Executable = 'pwsh.exe';

  static String wrapInlineCommand(
    String command, {
    String executable = windowsPowerShellExecutable,
  }) {
    return '$executable -NoProfile -ExecutionPolicy Bypass -Command ${_quoteForCmd(command.trim())}';
  }

  static String? tryUnwrapInlineCommand(String command) {
    return tryParseInlineCommand(command)?.command;
  }

  static PowerShellInlineCommand? tryParseInlineCommand(String command) {
    final match = RegExp(
      r'^\s*(powershell(?:\.exe)?|pwsh(?:\.exe)?)\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-Command\s+"(.*)"\s*$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(command);
    if (match == null) {
      return null;
    }

    return PowerShellInlineCommand(
      executable: _normalizeExecutable(match.group(1)!),
      command: _unescapeCmdQuoted(match.group(2)!),
    );
  }

  static bool isPowerShellScriptPath(String path) {
    return path.trim().toLowerCase().endsWith('.ps1');
  }

  static bool isPowerShell7Executable(String? executable) {
    if (executable == null) {
      return false;
    }
    final normalized = executable.trim().replaceAll('/', r'\').toLowerCase();
    return normalized == 'pwsh' || normalized == powerShell7Executable || normalized.endsWith(r'\pwsh.exe');
  }

  static String _normalizeExecutable(String executable) {
    return isPowerShell7Executable(executable) ? powerShell7Executable : windowsPowerShellExecutable;
  }

  static String _quoteForCmd(String value) {
    final buffer = StringBuffer('"');
    for (final codeUnit in value.codeUnits) {
      final character = String.fromCharCode(codeUnit);
      if (character == '^') {
        buffer.write('^^');
      } else if (character == '"') {
        buffer.write('^"');
      } else {
        buffer.write(character);
      }
    }
    buffer.write('"');
    return buffer.toString();
  }

  static String _unescapeCmdQuoted(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += 1) {
      final character = value[i];
      if (character == '^' && i + 1 < value.length) {
        final next = value[i + 1];
        if (next == '^' || next == '"') {
          buffer.write(next);
          i += 1;
          continue;
        }
      }
      buffer.write(character);
    }
    return buffer.toString();
  }
}
