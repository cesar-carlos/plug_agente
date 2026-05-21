import 'dart:io';

import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_execution_materializer.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_request_protector.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_runner_bridge.dart';
import 'package:test/test.dart';

const _testElevatedDefinition = AgentActionDefinition(
  id: 'action-1',
  name: 'Test',
  state: AgentActionState.active,
  config: CommandLineActionConfig(command: 'echo bridge'),
);

void main() {
  group('ElevatedActionRunnerBridge', () {
    late Directory tempDir;
    late ElevatedActionRequestProtector protector;
    late ElevatedActionExecutionMaterializer materializer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_runner_bridge_test_');
      final storageContext = GlobalStorageContext(appDirectoryPath: tempDir.path);
      protector = ElevatedActionRequestProtector(storageContext: storageContext);
      materializer = ElevatedActionExecutionMaterializer(storageContext: storageContext);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should return submit failure when scheduled task runner fails', () async {
      final bridge = ElevatedActionRunnerBridge(
        requestProtector: protector,
        materializer: materializer,
        scheduledTaskRunner: (_) async => ProcessResult(1, 1, 'failed', 'failed'),
      );

      final result = await bridge.submitExecution(
        executionId: 'exec-1',
        definition: _testElevatedDefinition,
      );

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as ActionRuntimeFailure).code, AgentActionFailureCode.elevatedSubmitFailed);
    });

    test('should succeed when request file is written and scheduled task starts', () async {
      final bridge = ElevatedActionRunnerBridge(
        requestProtector: protector,
        materializer: materializer,
        scheduledTaskRunner: (_) async => ProcessResult(0, 0, '', ''),
      );

      final result = await bridge.submitExecution(
        executionId: 'exec-2',
        definition: _testElevatedDefinition,
      );

      expect(result.isSuccess(), isTrue);
    });
  });
}
