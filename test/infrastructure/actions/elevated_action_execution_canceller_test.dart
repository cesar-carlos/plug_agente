import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_execution_canceller.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionExecutionCanceller', () {
    late Directory tempDir;
    late ElevatedActionExecutionCanceller canceller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_canceller_test_');
      canceller = ElevatedActionExecutionCanceller(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        now: () => DateTime.utc(2026, 5, 18, 12),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should write cancel marker, remove pending request and terminal status', () async {
      final requestPath = AgentActionElevatedConstants.requestFilePath(tempDir.path, 'exec-1');
      await File(requestPath).parent.create(recursive: true);
      await File(requestPath).writeAsString('{}');
      final materializedPath = AgentActionElevatedConstants.materializedFilePath(tempDir.path, 'exec-1');
      await File(materializedPath).parent.create(recursive: true);
      await File(materializedPath).writeAsString('{}');

      final result = await canceller.cancel(executionId: 'exec-1');

      expect(result.isSuccess(), isTrue);
      expect(
        File(AgentActionElevatedConstants.cancelFilePath(tempDir.path, 'exec-1')).existsSync(),
        isTrue,
      );
      expect(File(requestPath).existsSync(), isFalse);
      expect(
        File(AgentActionElevatedConstants.materializedFilePath(tempDir.path, 'exec-1')).existsSync(),
        isFalse,
      );

      final status =
          jsonDecode(
                await File(AgentActionElevatedConstants.statusFilePath(tempDir.path, 'exec-1')).readAsString(),
              )
              as Map<String, dynamic>;
      expect(status['status'], AgentActionExecutionStatus.killed.name);
      expect(status['failureCode'], AgentActionFailureCode.executionKilled);
    });

    test('should keep existing terminal status unchanged', () async {
      final statusPath = AgentActionElevatedConstants.statusFilePath(tempDir.path, 'exec-2');
      await File(statusPath).parent.create(recursive: true);
      await File(statusPath).writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.statusSchemaVersion,
          'executionId': 'exec-2',
          'status': 'succeeded',
          'finishedAt': DateTime.utc(2026, 5, 18, 12).toIso8601String(),
          'redactionApplied': true,
        }),
      );

      final result = await canceller.cancel(executionId: 'exec-2');

      expect(result.isSuccess(), isTrue);
      final status = jsonDecode(await File(statusPath).readAsString()) as Map<String, dynamic>;
      expect(status['status'], 'succeeded');
    });
  });
}
