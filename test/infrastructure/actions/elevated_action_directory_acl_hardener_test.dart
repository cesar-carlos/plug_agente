import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_directory_acl_hardener.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionDirectoryAclHardener', () {
    test('should skip ACL hardening outside Windows', () async {
      if (Platform.isWindows) {
        return;
      }

      final hardener = ElevatedActionDirectoryAclHardener();
      final outcome = await hardener.ensureSecured(r'C:\temp\plug');

      expect(outcome, ElevatedDirectoryAclOutcome.skippedNonWindows);
    });

    test('should restrict elevated directories with icacls on Windows', () async {
      if (!Platform.isWindows) {
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp('elevated_acl_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      String? capturedExecutable;
      List<String>? capturedArguments;
      final hardener = ElevatedActionDirectoryAclHardener(
        processRunner: (String executable, List<String> arguments) async {
          capturedExecutable = executable;
          capturedArguments = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );

      final outcome = await hardener.ensureSecured(tempDir.path);

      expect(outcome, ElevatedDirectoryAclOutcome.restricted);
      expect(capturedExecutable, 'icacls');
      expect(capturedArguments, isNotNull);
      expect(capturedArguments!.first, contains('agent_actions'));
      expect(capturedArguments, contains('/inheritance:r'));
      expect(
        Directory(AgentActionElevatedConstants.materializedDirectoryPath(tempDir.path)).existsSync(),
        isTrue,
      );
    });
  });
}
