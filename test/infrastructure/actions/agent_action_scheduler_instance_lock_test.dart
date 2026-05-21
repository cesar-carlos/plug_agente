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
  });
}
