import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/storage/icacls_command_runner.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

void main() {
  group('IcaclsCommandRunner', () {
    test('should combine multiple grants in one icacls invocation on Windows', () async {
      List<String>? capturedArgs;
      final runner = IcaclsCommandRunner(
        processRunner: (executable, arguments) async {
          capturedArgs = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );

      final outcome = await runner.grant(
        targetPath: r'C:\ProgramData\PlugAgente',
        grantEntries: <String>['*S-1-5-11:(OI)(CI)(M)', '*S-1-5-32-545:(OI)(CI)(M)'],
        operation: 'test',
      );

      if (Platform.isWindows) {
        expect(outcome.kind, IcaclsGrantOutcomeKind.success);
        expect(capturedArgs, <String>[
          r'C:\ProgramData\PlugAgente',
          '/grant',
          '*S-1-5-11:(OI)(CI)(M)',
          '/grant',
          '*S-1-5-32-545:(OI)(CI)(M)',
        ]);
      } else {
        expect(outcome.kind, IcaclsGrantOutcomeKind.skippedNonWindows);
      }
    });

    test('should return timeout outcome when icacls exceeds deadline', () async {
      final runner = IcaclsCommandRunner(
        timeout: const Duration(milliseconds: 50),
        processRunner: (executable, arguments) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return ProcessResult(0, 0, '', '');
        },
      );

      if (!Platform.isWindows) {
        return;
      }

      final outcome = await runner.grant(
        targetPath: r'C:\ProgramData\PlugAgente',
        grantEntries: <String>['*S-1-5-11:(M)'],
        operation: 'test_timeout',
      );

      expect(outcome.kind, IcaclsGrantOutcomeKind.timeout);
    });
  });
}
