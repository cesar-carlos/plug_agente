import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_request_processor.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedRequestProcessor', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'elevated_helper_processor_',
      );
      dbPath = ElevatedContract.databasePath(tempDir.path);
      await _seedDatabase(
        dbPath: dbPath,
        executionId: 'exec-1',
        actionId: 'action-1',
        command: 'echo hello',
        elevated: true,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'should process valid request and write terminal status file',
      () async {
        final requestsDir = Directory(
          ElevatedContract.requestsDirectory(tempDir.path),
        );
        await requestsDir.create(recursive: true);
        const nonce = 'nonce-1';
        final expiresAt = DateTime.utc(2026, 5, 18, 13);
        await File(
          ElevatedContract.requestFilePath(tempDir.path, 'exec-1'),
        ).writeAsString(
          jsonEncode(<String, Object?>{
            'version': ElevatedContract.requestSchemaVersion,
            'executionId': 'exec-1',
            'nonce': nonce,
            'createdAt': DateTime.utc(2026, 5, 18, 12).toIso8601String(),
            'expiresAt': expiresAt.toIso8601String(),
          }),
        );
        await File(
          ElevatedContract.materializedFilePath(tempDir.path, 'exec-1'),
        ).parent.create(recursive: true);
        await File(
          ElevatedContract.materializedFilePath(tempDir.path, 'exec-1'),
        ).writeAsString(
          jsonEncode(<String, Object?>{
            'version': ElevatedContract.materializedSchemaVersion,
            'executionId': 'exec-1',
            'nonce': nonce,
            'expiresAt': expiresAt.toIso8601String(),
            'actionType': 'commandLine',
            'launch': <String, Object?>{
              'executable': 'cmd.exe',
              'arguments': <String>['/c', 'echo hello'],
              'commandPreview': 'echo hello',
            },
          }),
        );

        final processor = ElevatedRequestProcessor(
          appDirectoryPath: tempDir.path,
          now: () => DateTime.utc(2026, 5, 18, 12, 1),
        );

        final processed = await processor.processPendingRequests();

        expect(processed, 1);
        expect(
          File(
            ElevatedContract.requestFilePath(tempDir.path, 'exec-1'),
          ).existsSync(),
          isFalse,
        );
        final statusFile = File(
          ElevatedContract.statusFilePath(tempDir.path, 'exec-1'),
        );
        expect(statusFile.existsSync(), isTrue);
        final status =
            jsonDecode(await statusFile.readAsString()) as Map<String, dynamic>;
        expect(status['status'], 'succeeded');
        expect(status['executionId'], 'exec-1');
      },
    );

    test('should reject request files with invalid createdAt', () async {
      await Directory(
        ElevatedContract.requestsDirectory(tempDir.path),
      ).create(recursive: true);
      await File(
        ElevatedContract.requestFilePath(tempDir.path, 'exec-1'),
      ).writeAsString(
        jsonEncode(<String, Object?>{
          'version': ElevatedContract.requestSchemaVersion,
          'executionId': 'exec-1',
          'nonce': 'nonce-1',
          'createdAt': 'not-a-date',
          'expiresAt': DateTime.utc(2026, 5, 18, 13).toIso8601String(),
        }),
      );

      final processor = ElevatedRequestProcessor(
        appDirectoryPath: tempDir.path,
        now: () => DateTime.utc(2026, 5, 18, 12),
      );

      await processor.processPendingRequests();

      final status =
          jsonDecode(
                await File(
                  ElevatedContract.statusFilePath(tempDir.path, 'exec-1'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(
        status['failureCode'],
        'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
      );
    });

    test(
      'should fail with ACTION_ELEVATED_NOT_CONFIGURED when policy does not approve elevated execution',
      () async {
        // Re-seed sem `elevated.runElevated=true`.
        await File(dbPath).delete();
        await _seedDatabase(
          dbPath: dbPath,
          executionId: 'exec-2',
          actionId: 'action-2',
          command: 'echo hello',
          elevated: false,
        );

        await Directory(
          ElevatedContract.requestsDirectory(tempDir.path),
        ).create(recursive: true);
        const nonce = 'nonce-2';
        final expiresAt = DateTime.utc(2026, 5, 18, 13);
        await File(
          ElevatedContract.requestFilePath(tempDir.path, 'exec-2'),
        ).writeAsString(
          jsonEncode(<String, Object?>{
            'version': ElevatedContract.requestSchemaVersion,
            'executionId': 'exec-2',
            'nonce': nonce,
            'createdAt': DateTime.utc(2026, 5, 18, 12).toIso8601String(),
            'expiresAt': expiresAt.toIso8601String(),
          }),
        );
        await File(
          ElevatedContract.materializedFilePath(tempDir.path, 'exec-2'),
        ).parent.create(recursive: true);
        await File(
          ElevatedContract.materializedFilePath(tempDir.path, 'exec-2'),
        ).writeAsString(
          jsonEncode(<String, Object?>{
            'version': ElevatedContract.materializedSchemaVersion,
            'executionId': 'exec-2',
            'nonce': nonce,
            'expiresAt': expiresAt.toIso8601String(),
            'actionType': 'commandLine',
            'launch': <String, Object?>{
              'executable': 'cmd.exe',
              'arguments': <String>['/c', 'echo hello'],
              'commandPreview': 'echo hello',
            },
          }),
        );

        final processor = ElevatedRequestProcessor(
          appDirectoryPath: tempDir.path,
          now: () => DateTime.utc(2026, 5, 18, 12, 1),
        );

        await processor.processPendingRequests();

        final status =
            jsonDecode(
                  await File(
                    ElevatedContract.statusFilePath(tempDir.path, 'exec-2'),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        expect(status['status'], 'failed');
        expect(status['failureCode'], 'ACTION_ELEVATED_NOT_CONFIGURED');
      },
    );

    test('should reject expired request files', () async {
      await Directory(
        ElevatedContract.requestsDirectory(tempDir.path),
      ).create(recursive: true);
      await File(
        ElevatedContract.requestFilePath(tempDir.path, 'exec-1'),
      ).writeAsString(
        jsonEncode(<String, Object?>{
          'version': ElevatedContract.requestSchemaVersion,
          'executionId': 'exec-1',
          'nonce': 'nonce-1',
          'createdAt': DateTime.utc(2026, 5, 18, 10).toIso8601String(),
          'expiresAt': DateTime.utc(2026, 5, 18, 10, 5).toIso8601String(),
        }),
      );

      final processor = ElevatedRequestProcessor(
        appDirectoryPath: tempDir.path,
        now: () => DateTime.utc(2026, 5, 18, 12),
      );

      await processor.processPendingRequests();

      final status =
          jsonDecode(
                await File(
                  ElevatedContract.statusFilePath(tempDir.path, 'exec-1'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(status['status'], 'failed');
      expect(
        status['failureCode'],
        'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
      );
    });
  });
}

Future<void> _seedDatabase({
  required String dbPath,
  required String executionId,
  required String actionId,
  required String command,
  required bool elevated,
}) async {
  await File(dbPath).parent.create(recursive: true);
  final database = sqlite3.open(dbPath);
  try {
    database.execute('''
CREATE TABLE agent_action_definition_table (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL,
  state TEXT NOT NULL,
  config_json TEXT NOT NULL,
  policies_json TEXT NOT NULL,
  definition_version INTEGER NOT NULL DEFAULT 1,
  definition_snapshot_hash TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    database.execute('''
CREATE TABLE agent_action_execution_table (
  id TEXT NOT NULL PRIMARY KEY,
  action_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  status TEXT NOT NULL,
  requested_at INTEGER NOT NULL,
  source TEXT NOT NULL,
  redaction_applied INTEGER NOT NULL DEFAULT 0,
  stdout_truncated INTEGER NOT NULL DEFAULT 0,
  stderr_truncated INTEGER NOT NULL DEFAULT 0
)
''');
    final nowMs = DateTime.utc(2026, 5, 18).millisecondsSinceEpoch;
    database.execute(
      '''
INSERT INTO agent_action_definition_table (
  id, name, type, state, config_json, policies_json, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''',
      <Object?>[
        actionId,
        'Test action',
        'commandLine',
        'active',
        jsonEncode(<String, Object?>{'command': command}),
        jsonEncode(<String, Object?>{
          'timeout': {'maxRuntimeMs': 60000},
          'capture': {'maxCapturedOutputBytes': 4096},
          'exitCode': {
            'acceptedExitCodes': [0],
          },
          'elevated': {'runElevated': elevated},
        }),
        nowMs,
        nowMs,
      ],
    );
    database.execute(
      '''
INSERT INTO agent_action_execution_table (
  id, action_id, action_type, status, requested_at, source
) VALUES (?, ?, ?, ?, ?, ?)
''',
      <Object?>[
        executionId,
        actionId,
        'commandLine',
        'running',
        nowMs,
        'localUi',
      ],
    );
  } finally {
    database.dispose();
  }
}
