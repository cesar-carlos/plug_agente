import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';

void main() {
  group('PowerShellCommandLine', () {
    test('wraps inline command with powershell.exe flags', () {
      expect(
        PowerShellCommandLine.wrapInlineCommand('Get-Process'),
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Process"',
      );
    });

    test('wraps inline command with pwsh.exe flags', () {
      expect(
        PowerShellCommandLine.wrapInlineCommand(
          'Get-Process',
          executable: PowerShellCommandLine.powerShell7Executable,
        ),
        'pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Process"',
      );
    });

    test('protects command metacharacters and preserves secret placeholders', () {
      const command = r'Write-Output "hello & world" | Set-Content "${secret:out_path}"';

      final wrapped = PowerShellCommandLine.wrapInlineCommand(command);

      expect(wrapped, startsWith('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "'));
      expect(wrapped, contains('hello & world'));
      expect(wrapped, contains('| Set-Content'));
      expect(wrapped, contains(r'${secret:out_path}'));
      expect(wrapped, contains('^"hello & world^"'));
      expect(PowerShellCommandLine.tryUnwrapInlineCommand(wrapped), command);
    });

    test('parses generated PowerShell 7 command line strings', () {
      final parsed = PowerShellCommandLine.tryParseInlineCommand(
        PowerShellCommandLine.wrapInlineCommand(
          'Write-Output "ok"',
          executable: PowerShellCommandLine.powerShell7Executable,
        ),
      );

      expect(parsed, isNotNull);
      expect(parsed!.executable, PowerShellCommandLine.powerShell7Executable);
      expect(parsed.command, 'Write-Output "ok"');
    });

    test('does not unwrap unrelated command line strings', () {
      expect(PowerShellCommandLine.tryUnwrapInlineCommand('powershell.exe Get-Process'), isNull);
      expect(PowerShellCommandLine.tryUnwrapInlineCommand('cmd.exe /C dir'), isNull);
    });

    test('recognizes ps1 script paths case-insensitively', () {
      expect(PowerShellCommandLine.isPowerShellScriptPath(r'C:\Jobs\backup.PS1'), isTrue);
      expect(PowerShellCommandLine.isPowerShellScriptPath(r'C:\Jobs\backup.cmd'), isFalse);
    });

    test('recognizes PowerShell 7 executable paths', () {
      expect(PowerShellCommandLine.isPowerShell7Executable('pwsh.exe'), isTrue);
      expect(PowerShellCommandLine.isPowerShell7Executable(r'C:\Program Files\PowerShell\7\pwsh.exe'), isTrue);
      expect(PowerShellCommandLine.isPowerShell7Executable('powershell.exe'), isFalse);
      expect(PowerShellCommandLine.isPowerShell7Executable(null), isFalse);
    });
  });
}
