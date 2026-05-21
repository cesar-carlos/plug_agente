import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';

void main() {
  group('ActionCommandNormalizer', () {
    const normalizer = ActionCommandNormalizer();

    test('should build cmd invocation for free command line with pipes', () {
      final result = normalizer.normalizeCommandLine(
        actionId: 'action-1',
        command: '  echo ok | findstr ok  ',
      );

      expect(result.isSuccess(), isTrue);
      final invocation = result.getOrThrow();
      expect(invocation.executable, 'cmd.exe');
      expect(invocation.arguments, const <String>['/C', 'echo ok | findstr ok']);
      expect(invocation.runInShell, isFalse);
      expect(invocation.mode, ProcessStartMode.normal);
      expect(invocation.redactedPreview, 'cmd.exe /C [REDACTED_COMMAND]');
      expect(invocation.normalizedCommandLength, 20);
    });

    test('should build direct invocation for exe with structured arguments', () {
      final result = normalizer.normalizeExecutable(
        actionId: 'action-1',
        executableCanonicalPath: r'C:\Tools\job.exe',
        arguments: const <String>['--mode', 'daily'],
      );

      expect(result.isSuccess(), isTrue);
      final invocation = result.getOrThrow();
      expect(invocation.executable, r'C:\Tools\job.exe');
      expect(invocation.arguments, const <String>['--mode', 'daily']);
      expect(invocation.runInShell, isFalse);
      expect(invocation.redactedPreview, r'C:\Tools\job.exe [REDACTED_ARG_0] [REDACTED_ARG_1]');
    });

    test('should run batch files through cmd.exe with structured arguments', () {
      final result = normalizer.normalizeExecutable(
        actionId: 'action-1',
        executableCanonicalPath: r'C:\Program Files\Tools\job.bat',
        arguments: const <String>['daily'],
      );

      expect(result.isSuccess(), isTrue);
      final invocation = result.getOrThrow();
      expect(invocation.executable, 'cmd.exe');
      expect(invocation.arguments, <String>['/C', r'C:\Program Files\Tools\job.bat', 'daily']);
      expect(invocation.runInShell, isFalse);
      expect(
        invocation.redactedPreview,
        r'cmd.exe /C "C:\Program Files\Tools\job.bat" [REDACTED_ARG_0]',
      );
    });

    test('should reject arguments with embedded newlines', () {
      final result = normalizer.normalizeExecutable(
        actionId: 'action-1',
        executableCanonicalPath: r'C:\Tools\job.exe',
        arguments: const <String>['line1\nline2'],
        phase: 'execution_preflight',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context, containsPair('reason', 'invalid_argument_characters'));
    });

    test('should reject blank executable argument', () {
      final result = normalizer.normalizeExecutable(
        actionId: 'action-1',
        executableCanonicalPath: r'C:\Tools\job.exe',
        arguments: const <String>['  '],
        phase: 'execution_preflight',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context, containsPair('field', 'arguments'));
      expect(failure.context, containsPair('phase', 'execution_preflight'));
    });

    test('should build powershell invocation for ps1 script', () {
      final result = normalizer.normalizeScript(
        actionId: 'action-1',
        scriptCanonicalPath: r'C:\Jobs\daily.ps1',
        interpreterCanonicalPath: 'powershell.exe',
        arguments: const <String>['-Verbose'],
      );

      expect(result.isSuccess(), isTrue);
      final invocation = result.getOrThrow();
      expect(invocation.executable, 'powershell.exe');
      expect(
        invocation.arguments,
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          r'C:\Jobs\daily.ps1',
          '-Verbose',
        ],
      );
    });

    test('should build cmd invocation for bat script', () {
      final result = normalizer.normalizeScript(
        actionId: 'action-1',
        scriptCanonicalPath: r'C:\Jobs\daily.bat',
        interpreterCanonicalPath: 'cmd.exe',
        arguments: const <String>['daily'],
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().arguments, <String>['/C', r'C:\Jobs\daily.bat', 'daily']);
    });

    test('should build java -jar invocation for jar action', () {
      final result = normalizer.normalizeJar(
        actionId: 'action-1',
        jarCanonicalPath: r'C:\Apps\job.jar',
        javaExecutablePath: r'C:\Java\bin\java.exe',
        arguments: const <String>['--verbose'],
      );

      expect(result.isSuccess(), isTrue);
      final invocation = result.getOrThrow();
      expect(invocation.executable, r'C:\Java\bin\java.exe');
      expect(
        invocation.arguments,
        <String>[
          '-jar',
          r'C:\Apps\job.jar',
          '--verbose',
        ],
      );
      expect(
        invocation.redactedPreview,
        r'C:\Java\bin\java.exe -jar C:\Apps\job.jar [REDACTED_ARG_0] (job.jar)',
      );
    });

    test('should reject blank command line', () {
      final result = normalizer.normalizeCommandLine(
        actionId: 'action-1',
        command: '   ',
        phase: 'execution_preflight',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure, isA<ActionValidationFailure>());
      expect(failure.context, containsPair('field', 'command'));
      expect(failure.context, containsPair('phase', 'execution_preflight'));
    });
  });
}
