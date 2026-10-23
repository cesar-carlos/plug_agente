import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_launch_spec.dart';
import 'package:plug_agente_elevated_runner/src/elevated_process_runner.dart';
import 'package:plug_agente_elevated_runner/src/elevated_sqlite_store.dart';
import 'package:test/test.dart';

void main() {
  test('disabled captures never retain process output', () async {
    final directory = await Directory.systemTemp.createTemp(
      'elevated_capture_regression_',
    );
    try {
      final result =
          await ElevatedProcessRunner(appDirectoryPath: directory.path).run(
            context: const ElevatedExecutionContext(
              executionId: 'run',
              actionId: 'action',
              actionType: 'commandLine',
              definitionState: 'active',
              config: {},
              policies: {
                'elevated': {'runElevated': true},
                'capture': {'captureStdout': false, 'captureStderr': false},
              },
            ),
            launch: const ElevatedLaunchSpec(
              executable: 'cmd.exe',
              arguments: ['/d', '/c', 'echo do-not-retain'],
              commandPreview: '[REDACTED]',
            ),
            materializedNonce: 'nonce',
          );
      expect(result.status, 'succeeded', reason: result.failureMessage);
      expect(result.stdoutText, isNull);
      expect(result.stderrText, isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
