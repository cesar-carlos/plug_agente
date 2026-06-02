import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_directory_acl_normalizer.dart';
import 'package:plug_agente/infrastructure/storage/icacls_command_runner.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

void main() {
  group('GlobalStorageDirectoryAclNormalizer', () {
    test('should grant directory ACL entries in one invocation on Windows', () async {
      final calls = <List<String>>[];
      final normalizer = GlobalStorageDirectoryAclNormalizer(
        commandRunner: IcaclsCommandRunner(
          processRunner: (executable, arguments) async {
            calls.add(arguments);
            return ProcessResult(0, 0, '', '');
          },
        ),
      );

      final outcome = await normalizer.normalizeDirectory(r'C:\ProgramData\PlugAgente');

      if (Platform.isWindows) {
        expect(outcome.isSuccess, isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.where((arg) => arg == '/grant').length, 2);
      } else {
        expect(outcome.kind, IcaclsGrantOutcomeKind.skippedNonWindows);
      }
    });

    test('should grant file ACL entry on Windows', () async {
      final calls = <List<String>>[];
      final normalizer = GlobalStorageDirectoryAclNormalizer(
        commandRunner: IcaclsCommandRunner(
          processRunner: (executable, arguments) async {
            calls.add(arguments);
            return ProcessResult(0, 0, '', '');
          },
        ),
      );

      final outcome = await normalizer.normalizeFile(r'C:\ProgramData\PlugAgente\agent_action_scheduler.lock');

      if (Platform.isWindows) {
        expect(outcome.isSuccess, isTrue);
        expect(calls.single, contains(r'C:\ProgramData\PlugAgente\agent_action_scheduler.lock'));
      } else {
        expect(outcome.kind, IcaclsGrantOutcomeKind.skippedNonWindows);
      }
    });
  });
}
