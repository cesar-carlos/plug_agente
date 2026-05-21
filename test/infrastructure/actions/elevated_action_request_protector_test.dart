import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_request_protector.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionRequestProtector', () {
    late Directory tempDir;
    late ElevatedActionRequestProtector protector;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_request_protector_test_');
      protector = ElevatedActionRequestProtector(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        now: () => DateTime.utc(2026, 5, 18, 12),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should write request file with execution id and nonce only', () async {
      final result = await protector.writeProtectedRequest(executionId: 'exec-1');

      expect(result.isSuccess(), isTrue);
      final path = AgentActionElevatedConstants.requestFilePath(tempDir.path, 'exec-1');
      final file = File(path);
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(json['version'], AgentActionElevatedConstants.requestSchemaVersion);
      expect(json['executionId'], 'exec-1');
      expect(json['nonce'], isNotEmpty);
      expect(json.containsKey('command'), isFalse);
    });

    test('should reject execution id with path traversal characters', () async {
      final result = await protector.writeProtectedRequest(executionId: '../exec-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });
  });
}
