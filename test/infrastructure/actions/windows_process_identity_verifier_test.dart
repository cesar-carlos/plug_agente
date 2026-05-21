import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_identity_verifier.dart';
void main() {
  group('WindowsProcessIdentityVerifier.executablePathsMatch', () {
    test('should match full paths after normalization', () {
      expect(
        WindowsProcessIdentityVerifier.executablePathsMatch(
          r'C:\Windows\System32\cmd.exe',
          'c:/windows/system32/cmd.exe',
        ),
        isTrue,
      );
    });

    test('should match short executable name against full image path', () {
      expect(
        WindowsProcessIdentityVerifier.executablePathsMatch('cmd.exe', r'C:\Windows\System32\cmd.exe'),
        isTrue,
      );
    });

    test('should reject different executables', () {
      expect(
        WindowsProcessIdentityVerifier.executablePathsMatch('notepad.exe', r'C:\Windows\System32\cmd.exe'),
        isFalse,
      );
    });
  });

  group('WindowsProcessIdentityVerifier.startedAtMatches', () {
    test('should accept creation time within tolerance', () {
      final expected = DateTime.utc(2026, 5, 18, 12);
      final actual = expected.add(const Duration(seconds: 10));

      expect(
        WindowsProcessIdentityVerifier.startedAtMatches(
          expected: expected,
          actual: actual,
          tolerance: AgentActionProcessConstants.processIdentityStartedAtTolerance,
        ),
        isTrue,
      );
    });

    test('should reject creation time outside tolerance', () {
      final expected = DateTime.utc(2026, 5, 18, 12);
      final actual = expected.add(const Duration(minutes: 2));

      expect(
        WindowsProcessIdentityVerifier.startedAtMatches(
          expected: expected,
          actual: actual,
          tolerance: AgentActionProcessConstants.processIdentityStartedAtTolerance,
        ),
        isFalse,
      );
    });
  });

  group('WindowsProcessIdentityVerifier.verify', () {
    test('should skip checks on non-Windows platforms', () {
      if (Platform.isWindows) {
        return;
      }

      expect(
        WindowsProcessIdentityVerifier.verify(
          executionId: 'execution-1',
          pid: 1,
          expectedExecutable: 'cmd.exe',
          expectedStartedAt: DateTime.utc(2026, 5, 18),
        ),
        isNull,
      );
    });

    test('should confirm child process executable on Windows', () async {
      if (!Platform.isWindows) {
        return;
      }

      final process = await Process.start(Platform.executable, ['--version']);
      addTearDown(() async {
        if (process.pid > 0) {
          process.kill();
        }
        await process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      });

      expect(
        WindowsProcessIdentityVerifier.verify(
          executionId: 'execution-1',
          pid: process.pid,
          expectedExecutable: Platform.executable,
        ),
        isNull,
      );
    });

    test('should reject mismatched executable on Windows', () async {
      if (!Platform.isWindows) {
        return;
      }

      final process = await Process.start(Platform.executable, ['--version']);
      addTearDown(() async {
        if (process.pid > 0) {
          process.kill();
        }
        await process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      });

      final failure = WindowsProcessIdentityVerifier.verify(
        executionId: 'execution-1',
        pid: process.pid,
        expectedExecutable: 'definitely-not-running-this-executable.exe',
      );

      expect(failure, isA<ActionRuntimeFailure>());
      expect((failure! as ActionRuntimeFailure).code, AgentActionFailureCode.processIdentityMismatch);
      expect(
        failure.context,
        containsPair('reason', AgentActionProcessConstants.processIdentityMismatchReason),
      );
    });
  });
}
