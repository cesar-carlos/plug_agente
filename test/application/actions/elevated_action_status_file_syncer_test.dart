import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionStatusFileSyncer', () {
    late Directory tempDir;
    late ElevatedActionStatusFileSyncer syncer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_status_syncer_test_');
      syncer = ElevatedActionStatusFileSyncer(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        now: () => DateTime.utc(2026, 5, 18, 12),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should map terminal status file to process result and delete file', () async {
      final statusPath = AgentActionElevatedConstants.statusFilePath(tempDir.path, 'exec-1');
      await File(statusPath).parent.create(recursive: true);
      await File(statusPath).writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.statusSchemaVersion,
          'executionId': 'exec-1',
          'status': 'succeeded',
          'finishedAt': DateTime.utc(2026, 5, 18, 12, 0, 5).toIso8601String(),
          'exitCode': 0,
          'redactionApplied': true,
          'stdoutText': 'ok',
        }),
      );

      final result = await syncer.waitForTerminalResult(
        executionId: 'exec-1',
        processStartedAt: DateTime.utc(2026, 5, 18, 12),
        timeout: const Duration(seconds: 2),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.succeeded);
      expect(File(statusPath).existsSync(), isFalse);
    });

    test('should propagate helper failure codes into process result', () async {
      final statusPath = AgentActionElevatedConstants.statusFilePath(tempDir.path, 'exec-2');
      await File(statusPath).parent.create(recursive: true);
      await File(statusPath).writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.statusSchemaVersion,
          'executionId': 'exec-2',
          'status': 'failed',
          'finishedAt': DateTime.utc(2026, 5, 18, 12, 0, 5).toIso8601String(),
          'failureCode': 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
          'failureMessage': 'Request expired before processing.',
          'redactionApplied': true,
        }),
      );

      final result = await syncer.waitForTerminalResult(
        executionId: 'exec-2',
        processStartedAt: DateTime.utc(2026, 5, 18, 12),
        timeout: const Duration(seconds: 2),
      );

      expect(result.isSuccess(), isTrue);
      final output = result.getOrThrow();
      expect(output.status, AgentActionExecutionStatus.failed);
      expect(output.failureCode, 'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED');
      expect(output.failureMessage, 'Request expired before processing.');
    });

    test('should record elevated status file metrics', () async {
      final metrics = MetricsCollector();
      final metricsSyncer = ElevatedActionStatusFileSyncer(
        storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        metrics: metrics,
        now: () => DateTime.utc(2026, 5, 18, 12),
      );

      final statusPath = AgentActionElevatedConstants.statusFilePath(tempDir.path, 'exec-metrics');
      await File(statusPath).parent.create(recursive: true);
      await File(statusPath).writeAsString(
        jsonEncode(<String, Object?>{
          'version': AgentActionElevatedConstants.statusSchemaVersion,
          'executionId': 'exec-metrics',
          'status': 'succeeded',
          'finishedAt': DateTime.utc(2026, 5, 18, 12, 0, 1).toIso8601String(),
          'exitCode': 0,
          'redactionApplied': true,
        }),
      );

      await metricsSyncer.waitForTerminalResult(
        executionId: 'exec-metrics',
        processStartedAt: DateTime.utc(2026, 5, 18, 12),
        timeout: const Duration(seconds: 2),
      );

      final timeoutResult =
          await ElevatedActionStatusFileSyncer(
            storageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
            metrics: metrics,
            now: () => DateTime.utc(2026, 5, 18, 12, 30),
          ).waitForTerminalResult(
            executionId: 'exec-timeout',
            processStartedAt: DateTime.utc(2026, 5, 18, 12),
            timeout: Duration.zero,
          );

      expect(timeoutResult.isError(), isTrue);
      final snapshot = metrics.getSnapshot();
      expect(snapshot['agent_action_elevated_status_file_terminal'], 1);
      expect(snapshot['agent_action_elevated_status_file_wait_timeout'], 1);
    });
  });
}
