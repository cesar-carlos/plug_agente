import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_execution_materializer.dart';
import 'package:plug_agente/infrastructure/actions/elevated_protected_request.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionExecutionMaterializer', () {
    late Directory tempDir;
    late ElevatedActionExecutionMaterializer materializer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_materializer_test_');
      materializer = ElevatedActionExecutionMaterializer(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should write materialized commandLine launch plan', () async {
      final protectedRequest = ElevatedProtectedRequest(
        executionId: 'exec-1',
        nonce: 'nonce-1',
        expiresAt: DateTime.utc(2026, 5, 18, 13),
        requestPath: 'ignored',
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Echo',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'echo hello'),
      );

      final result = await materializer.writeMaterializedLaunchPlan(
        protectedRequest: protectedRequest,
        definition: definition,
      );

      expect(result.isSuccess(), isTrue);
      final materialized =
          jsonDecode(
                await File(AgentActionElevatedConstants.materializedFilePath(tempDir.path, 'exec-1')).readAsString(),
              )
              as Map<String, dynamic>;
      expect(materialized['nonce'], 'nonce-1');
      expect(materialized['actionType'], 'commandLine');
      final launch = materialized['launch'] as Map<String, dynamic>;
      expect(launch['executable'], 'cmd.exe');
      expect(launch['arguments'], <String>['/C', 'echo hello']);
      expect(launch['commandPreview'], 'cmd.exe /C [REDACTED_COMMAND]');
    });

    test('should keep redacted command preview when capture policy disables output redaction', () async {
      final protectedRequest = ElevatedProtectedRequest(
        executionId: 'exec-sensitive',
        nonce: 'nonce-sensitive',
        expiresAt: DateTime.utc(2026, 5, 18, 13),
        requestPath: 'ignored',
      );
      const definition = AgentActionDefinition(
        id: 'action-sensitive',
        name: 'Echo',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'echo secret-token'),
        policies: AgentActionDefinitionPolicies(
          capture: AgentActionCapturePolicy(redactBeforePersisting: false),
        ),
      );

      final result = await materializer.writeMaterializedLaunchPlan(
        protectedRequest: protectedRequest,
        definition: definition,
      );

      expect(result.isSuccess(), isTrue);
      final materialized =
          jsonDecode(
                await File(
                  AgentActionElevatedConstants.materializedFilePath(tempDir.path, 'exec-sensitive'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final launch = materialized['launch'] as Map<String, dynamic>;
      expect(launch['commandPreview'], 'cmd.exe /C [REDACTED_COMMAND]');
    });

    test('should reject unresolved secret placeholders', () async {
      final protectedRequest = ElevatedProtectedRequest(
        executionId: 'exec-2',
        nonce: 'nonce-2',
        expiresAt: DateTime.utc(2026, 5, 18, 13),
        requestPath: 'ignored',
      );
      const definition = AgentActionDefinition(
        id: 'action-2',
        name: 'Secret',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api_key}'),
      );

      final result = await materializer.writeMaterializedLaunchPlan(
        protectedRequest: protectedRequest,
        definition: definition,
      );

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as ActionRuntimeFailure).code, AgentActionFailureCode.secretUnavailable);
    });
  });
}
