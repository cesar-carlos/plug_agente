import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_scheduler_instance_lock.dart';

void main() {
  group('AgentActionSchedulerInstanceLock', () {
    late Directory tempDir;
    late GlobalStorageContext storageContext;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('plug_agente_scheduler_lock_');
      storageContext = GlobalStorageContext(appDirectoryPath: tempDir.path);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // On Windows the lock file handle may still be releasing briefly.
      }
    });

    test('should allow acquire and release in sequence', () async {
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        runtimeIdentity: const AgentRuntimeIdentity(
          runtimeInstanceId: 'inst-lock',
          runtimeSessionId: 'sess-lock',
        ),
        currentPid: () => 4242,
      );

      final acquire = await lock.tryAcquire();
      expect(acquire.isSuccess(), isTrue);
      expect(lock.isHeld, isTrue);

      await lock.release();
      expect(lock.isHeld, isFalse);

      final secondAcquire = await lock.tryAcquire();
      expect(secondAcquire.isSuccess(), isTrue);
      await lock.release();
    });

    test('should reject second acquire while first lock is held', () async {
      final first = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        currentPid: () => 1001,
      );
      final second = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        currentPid: () => 1002,
      );

      expect((await first.tryAcquire()).isSuccess(), isTrue);

      final blocked = await second.tryAcquire();
      expect(blocked.isError(), isTrue);
      final failure = blocked.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.schedulerBootstrapFailed);
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );

      await first.release();
      expect((await second.tryAcquire()).isSuccess(), isTrue);
      await second.release();
    });

    test('should classify sharing violation as scheduler_instance_locked', () async {
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        openLockFile: (_) async {
          throw const FileSystemException(
            'Failed to open lock file.',
            r'C:\agent_action_scheduler.lock',
            OSError(
              'The process cannot access the file because it is being used by another process.',
              32,
            ),
          );
        },
      );

      final acquire = await lock.tryAcquire();
      expect(acquire.isError(), isTrue);
      final failure = acquire.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );
      expect(failure.context['os_error_code'], 32);
      expect(failure.context['lock_file_path'], contains('agent_action_scheduler.lock'));
    });

    test('should classify access denied as scheduler_storage_access_denied', () async {
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        openLockFile: (_) async {
          throw const FileSystemException(
            'Failed to open lock file.',
            r'C:\agent_action_scheduler.lock',
            OSError('Access is denied.', 5),
          );
        },
      );

      final acquire = await lock.tryAcquire();
      expect(acquire.isError(), isTrue);
      final failure = acquire.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.schedulerStorageAccessDeniedReason,
      );
      expect(failure.context['os_error_code'], 5);
      expect(failure.context['lock_file_path'], contains('agent_action_scheduler.lock'));
    });

    test('should classify unexpected filesystem error as scheduler_bootstrap_failed', () async {
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        openLockFile: (_) async {
          throw const FileSystemException(
            'Failed to open lock file.',
            r'C:\agent_action_scheduler.lock',
            OSError('The system cannot find the path specified.', 3),
          );
        },
      );

      final acquire = await lock.tryAcquire();
      expect(acquire.isError(), isTrue);
      final failure = acquire.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.schedulerBootstrapFailedReason,
      );
      expect(failure.context['os_error_code'], 3);
      expect(failure.context['lock_file_path'], contains('agent_action_scheduler.lock'));
    });
  });
}
