import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_stale_lock_recovery.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_lifetime_checker.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_directory_acl_normalizer.dart';
import 'package:plug_agente/infrastructure/storage/icacls_command_runner.dart';

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

    GlobalStorageAclBootstrap noopBootstrap() {
      return GlobalStorageAclBootstrap(
        normalizer: GlobalStorageDirectoryAclNormalizer(
          commandRunner: IcaclsCommandRunner(
            processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
          ),
        ),
      );
    }

    WindowsProcessLifetimeChecker alwaysRunningChecker() {
      return WindowsProcessLifetimeChecker(processRunningPredicate: (_) async => true);
    }

    WindowsProcessLifetimeChecker neverRunningChecker() {
      return WindowsProcessLifetimeChecker(processRunningPredicate: (_) async => false);
    }

    test(
      'should normalize lock file ACL after successful acquire',
      () async {
        var fileNormalized = false;
        final lock = AgentActionSchedulerInstanceLock(
          storageContext: storageContext,
          aclBootstrap: GlobalStorageAclBootstrap(
            normalizer: GlobalStorageDirectoryAclNormalizer(
              commandRunner: IcaclsCommandRunner(
                processRunner: (executable, arguments) async {
                  if (arguments.first.contains('agent_action_scheduler.lock')) {
                    fileNormalized = true;
                  }
                  return ProcessResult(0, 0, '', '');
                },
              ),
            ),
          ),
        );

        expect((await lock.tryAcquire()).isSuccess(), isTrue);
        expect(fileNormalized, isTrue);
        await lock.release();
      },
      skip: Platform.isWindows ? false : 'Lock file ACL normalization requires Windows',
    );

    test('should allow acquire and release in sequence', () async {
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        runtimeIdentity: const AgentRuntimeIdentity(
          runtimeInstanceId: 'inst-lock',
          runtimeSessionId: 'sess-lock',
        ),
        currentPid: () => 4242,
        aclBootstrap: noopBootstrap(),
      );

      expect((await lock.tryAcquire()).isSuccess(), isTrue);
      expect(lock.isHeld, isTrue);
      await lock.release();
      expect(lock.isHeld, isFalse);
      expect((await lock.tryAcquire()).isSuccess(), isTrue);
      await lock.release();
    });

    test('should reject second acquire while first lock is held', () async {
      final first = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        currentPid: () => 1001,
        aclBootstrap: noopBootstrap(),
      );
      final second = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        currentPid: () => 1002,
        aclBootstrap: noopBootstrap(),
      );

      expect((await first.tryAcquire()).isSuccess(), isTrue);

      final blocked = await second.tryAcquire();
      expect(blocked.isError(), isTrue);
      final failure = blocked.exceptionOrNull()! as ActionAuthorizationFailure;
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
        aclBootstrap: noopBootstrap(),
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
    });

    test('should classify access denied with live pid as scheduler_instance_locked', () async {
      await File(p.join(tempDir.path, 'agent_action_scheduler.lock')).writeAsString(
        'pid=999001\nacquired_at=2020-01-01T00:00:00.000Z\n',
      );

      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        currentPid: () => 4242,
        aclBootstrap: noopBootstrap(),
        processLifetimeChecker: alwaysRunningChecker(),
        staleLockRecovery: SchedulerStaleLockRecovery(
          processLifetimeChecker: alwaysRunningChecker(),
        ),
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
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );
    });

    test('should classify access denied as scheduler_storage_access_denied', () async {
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        aclBootstrap: noopBootstrap(),
        processLifetimeChecker: neverRunningChecker(),
        staleLockRecovery: SchedulerStaleLockRecovery(
          processLifetimeChecker: neverRunningChecker(),
        ),
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
      expect(failure.context['lock_file_path'], contains('agent_action_scheduler.lock'));
    });

    test('should recover stale lock after access denied and retry acquire', () async {
      await File(p.join(tempDir.path, 'agent_action_scheduler.lock')).writeAsString(
        'pid=999001\nacquired_at=2020-01-01T00:00:00.000Z\n',
      );

      var openAttempts = 0;
      final lock = AgentActionSchedulerInstanceLock(
        storageContext: storageContext,
        currentPid: () => 4242,
        aclBootstrap: noopBootstrap(),
        processLifetimeChecker: neverRunningChecker(),
        staleLockRecovery: SchedulerStaleLockRecovery(
          processLifetimeChecker: neverRunningChecker(),
          aclBootstrap: noopBootstrap(),
        ),
        openLockFile: (file) async {
          openAttempts++;
          if (openAttempts == 1) {
            throw const FileSystemException(
              'Failed to open lock file.',
              r'C:\agent_action_scheduler.lock',
              OSError('Access is denied.', 5),
            );
          }
          return file.open(mode: FileMode.write);
        },
      );

      final acquire = await lock.tryAcquire();
      expect(acquire.isSuccess(), isTrue);
      expect(openAttempts, 2);
      await lock.release();
    });
  });
}
