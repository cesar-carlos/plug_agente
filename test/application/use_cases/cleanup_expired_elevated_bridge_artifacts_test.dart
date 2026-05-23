import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/application/use_cases/cleanup_expired_elevated_bridge_artifacts.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:test/test.dart';

void main() {
  group('CleanupExpiredElevatedBridgeArtifacts', () {
    late Directory tempDir;
    late CleanupExpiredElevatedBridgeArtifacts cleanup;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_bridge_cleanup_test_');
      cleanup = CleanupExpiredElevatedBridgeArtifacts(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        now: () => DateTime.utc(2026, 5, 18, 14),
        isWindows: () => true,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should delete expired request and materialized files', () async {
      final requestsDir = AgentActionElevatedConstants.requestsDirectoryPath(tempDir.path);
      await Directory(requestsDir).create(recursive: true);
      final expiredRequest = File(AgentActionElevatedConstants.requestFilePath(tempDir.path, 'exec-old'));
      await expiredRequest.writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.requestSchemaVersion,
          'executionId': 'exec-old',
          'nonce': 'nonce-old',
          'createdAt': DateTime.utc(2026, 5, 18, 12).toIso8601String(),
          'expiresAt': DateTime.utc(2026, 5, 18, 12, 5).toIso8601String(),
        }),
      );

      final freshRequest = File(AgentActionElevatedConstants.requestFilePath(tempDir.path, 'exec-fresh'));
      await freshRequest.writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.requestSchemaVersion,
          'executionId': 'exec-fresh',
          'nonce': 'nonce-fresh',
          'createdAt': DateTime.utc(2026, 5, 18, 13, 55).toIso8601String(),
          'expiresAt': DateTime.utc(2026, 5, 18, 14, 30).toIso8601String(),
        }),
      );

      final result = await cleanup();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 1);
      expect(expiredRequest.existsSync(), isFalse);
      expect(freshRequest.existsSync(), isTrue);
    });

    test('should record elevated bridge artifact purge metrics', () async {
      final metrics = MetricsCollector();
      cleanup = CleanupExpiredElevatedBridgeArtifacts(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        metrics: metrics,
        now: () => DateTime.utc(2026, 5, 18, 14),
        isWindows: () => true,
      );
      final requestsDir = AgentActionElevatedConstants.requestsDirectoryPath(tempDir.path);
      await Directory(requestsDir).create(recursive: true);
      final expiredRequest = File(AgentActionElevatedConstants.requestFilePath(tempDir.path, 'exec-metrics'));
      await expiredRequest.writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.requestSchemaVersion,
          'executionId': 'exec-metrics',
          'nonce': 'nonce-metrics',
          'createdAt': DateTime.utc(2026, 5, 18, 12).toIso8601String(),
          'expiresAt': DateTime.utc(2026, 5, 18, 12, 5).toIso8601String(),
        }),
      );

      final result = await cleanup();

      expect(result.getOrThrow(), 1);
      expect(metrics.getSnapshot()['agent_action_elevated_bridge_artifacts_purge'], 1);
    });
  });
}
