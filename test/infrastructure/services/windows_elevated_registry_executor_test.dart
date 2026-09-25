import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_entry.dart';
import 'package:plug_agente/infrastructure/services/windows_elevated_registry_executor.dart';

void main() {
  group('WindowsElevatedRegistryExecutor', () {
    test('encodeUtf16Le should produce little-endian code units', () {
      final bytes = WindowsElevatedRegistryExecutor.encodeUtf16Le('A');
      check(bytes.length).equals(2);
      check(bytes[0]).equals(65);
      check(bytes[1]).equals(0);
    });

    test('deleteRunValue should launch elevated encoded PowerShell', () async {
      final calls = <List<String>>[];
      final results = Queue<ProcessResult>.from(<ProcessResult>[
        ProcessResult(0, 0, '', ''),
      ]);

      final executor = WindowsElevatedRegistryExecutor(
        processRunner: (executable, arguments) async {
          calls.add(arguments);
          return results.removeFirst();
        },
      );

      final result = await executor.deleteRunValue(
        scope: StartupRegistryScope.localMachine,
        valueName: 'Plug Agente',
      );

      check(result.exitCode).equals(0);
      final command = calls.single.join(' ');
      check(command).contains('-EncodedCommand');
      check(command).contains('-Verb RunAs');
      check(command).contains('${WindowsElevatedRegistryExecutor.uacCancelledExitCode}');
      check(command).contains('${WindowsElevatedRegistryExecutor.accessDeniedExitCode}');
    });

    test('should report an unanswered UAC prompt as cancelled after the timeout', () async {
      final neverCompletes = Completer<ProcessResult>();
      final executor = WindowsElevatedRegistryExecutor(
        processRunner: (executable, arguments) => neverCompletes.future,
        elevationTimeout: const Duration(milliseconds: 10),
      );

      final result = await executor.deleteRunValue(
        scope: StartupRegistryScope.localMachine,
        valueName: 'Plug Agente',
      );

      check(WindowsElevatedRegistryExecutor.isUacCancelled(result)).isTrue();
      check('${result.stderr}').contains('not answered');
    });

    test('isUacCancelled should prefer exit code over localized text', () {
      final cancelled = ProcessResult(0, WindowsElevatedRegistryExecutor.uacCancelledExitCode, '', '');
      check(WindowsElevatedRegistryExecutor.isUacCancelled(cancelled)).isTrue();
      check(
        WindowsElevatedRegistryExecutor.isAccessDenied(
          ProcessResult(0, WindowsElevatedRegistryExecutor.accessDeniedExitCode, '', ''),
        ),
      ).isTrue();
    });
  });
}
