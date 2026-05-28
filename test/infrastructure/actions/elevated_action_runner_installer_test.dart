import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/elevated_action_runner_install_state.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_runner_installer.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionRunnerInstaller', () {
    late Directory tempDir;
    late File helperExecutable;
    late ElevatedActionRunnerInstaller installer;
    final recordedCommands = <List<String>>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_installer_test_');
      helperExecutable = File(
        p.join(
          File(Platform.resolvedExecutable).parent.path,
          AgentActionElevatedConstants.defaultHelperExecutableName,
        ),
      );
      if (helperExecutable.existsSync()) {
        await helperExecutable.delete();
      }
      await helperExecutable.writeAsString('');
      recordedCommands.clear();
      installer = ElevatedActionRunnerInstaller(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        processRunner: (String executable, List<String> arguments) async {
          recordedCommands.add(<String>[executable, ...arguments]);
          if (executable == 'schtasks' && arguments.contains('/Create')) {
            return ProcessResult(0, 0, '', '');
          }
          if (executable == 'schtasks' && arguments.contains('/Query')) {
            return ProcessResult(
              0,
              0,
              'TaskName: ${AgentActionElevatedConstants.scheduledTaskName}\n'
                  'Task To Run: "${helperExecutable.path}" --watch-requests "${tempDir.path}"\n',
              '',
            );
          }
          return ProcessResult(1, 1, '', 'not found');
        },
        isWindows: () => true,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      if (helperExecutable.existsSync()) {
        await helperExecutable.delete();
      }
    });

    test('should report helper missing when executable is absent', () async {
      if (helperExecutable.existsSync()) {
        await helperExecutable.delete();
      }

      final status = await installer.getStatus();

      expect(status.state, ElevatedActionRunnerInstallState.helperExecutableMissing);
    });

    test('should install scheduled task and write ready marker when helper exists', () async {
      final result = await installer.install(requestElevation: false);

      expect(result.isSuccess(), isTrue);
      expect(
        File(AgentActionElevatedConstants.readyMarkerPath(tempDir.path)).existsSync(),
        isTrue,
      );
      expect(
        recordedCommands.any(
          (List<String> command) => command.contains('/Create') && command.contains('/TN'),
        ),
        isTrue,
      );
      final status = await installer.getStatus();
      expect(status.state, ElevatedActionRunnerInstallState.ready);
    });

    test('should report helperPathChanged when scheduled task points to a different exe', () async {
      // Install once so the marker exists.
      await installer.install(requestElevation: false);

      // Re-register installer with a Query stub that simulates an outdated
      // /TR pointing to a different exe path (post-update scenario).
      installer = ElevatedActionRunnerInstaller(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        processRunner: (String executable, List<String> arguments) async {
          if (executable == 'schtasks' && arguments.contains('/Query')) {
            return ProcessResult(
              0,
              0,
              'TaskName: ${AgentActionElevatedConstants.scheduledTaskName}\n'
                  r'Task To Run: "C:\Old\Path\plug_agente_elevated_runner.exe" --watch-requests "C:\Old\Data"',
              '',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
        isWindows: () => true,
      );

      final status = await installer.getStatus();
      expect(status.state, ElevatedActionRunnerInstallState.helperPathChanged);
    });
  });
}
