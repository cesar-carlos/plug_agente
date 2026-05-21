import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_kill_guard.dart';

void main() {
  group('AgentActionProcessKillGuard', () {
    test('should reject when expected pid does not match active process', () async {
      final process = await Process.start(Platform.executable, ['--version']);
      addTearDown(() async {
        if (process.pid > 0) {
          process.kill();
        }
        await process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      });

      final failure = AgentActionProcessKillGuard.validateBeforeKill(
        executionId: 'execution-1',
        process: process,
        expectedPid: process.pid + 1,
      );

      expect(failure, isA<ActionRuntimeFailure>());
      expect((failure! as ActionRuntimeFailure).code, AgentActionFailureCode.processIdMismatch);
      expect(failure.context, containsPair('reason', AgentActionProcessConstants.pidMismatchReason));
    });

    test('should return null when pid matches and no OS metadata is provided', () async {
      final process = await Process.start(Platform.executable, ['--version']);
      addTearDown(() async {
        if (process.pid > 0) {
          process.kill();
        }
        await process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      });

      final failure = AgentActionProcessKillGuard.validateBeforeKill(
        executionId: 'execution-1',
        process: process,
        expectedPid: process.pid,
      );

      expect(failure, isNull);
    });
  });
}
