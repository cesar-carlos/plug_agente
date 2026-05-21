import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_captured_output_chunker.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_drift_mapper.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

void main() {
  group('AgentActionRepository', () {
    late AppDatabase database;
    late AgentActionRepository repository;

    setUp(() {
      database = AppDatabase(executor: NativeDatabase.memory());
      repository = AgentActionRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('should save and load action definition with config and policies', () async {
      final definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Transmit Data7 project',
        description: 'Runs Data7 executor',
        state: AgentActionState.active,
        config: DeveloperActionConfig.data7Executor(
          executorPath: const AgentActionPathReference(
            originalPath: r'C:\Data7\bin\Executor.exe',
            canonicalPath: r'C:\Data7\bin\Executor.exe',
            existsAtValidation: true,
          ),
          projectPath: const AgentActionPathReference(
            originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
          ),
          data7ConfigPath: const AgentActionPathReference(
            originalPath: r'C:\Data7\bin\Data7.Config',
          ),
          connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
          connectionLabel: 'Data7',
          connectionSnapshotHash: 'hash-redacted',
        ),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedBy: 'local-user',
            approvedAt: DateTime.utc(2026, 5, 15),
            approvalReason: 'Approved test',
          ),
          queue: const AgentActionQueuePolicy(
            maxConcurrent: 2,
            maxQueued: 10,
            queueTimeout: Duration(minutes: 2),
            concurrencyBehavior: AgentActionConcurrencyBehavior.reject,
          ),
          timeout: const AgentActionTimeoutPolicy(
            maxRuntime: Duration(minutes: 10),
          ),
          context: const AgentActionContextPolicy(
            allowedContextExtensions: {'.json'},
            maxContextBytes: 1024,
          ),
          exitCode: const AgentActionExitCodePolicy(
            acceptedExitCodes: {0, 2},
          ),
          path: const AgentActionPathPolicy(
            allowedWorkingDirectories: {r'C:\Data7'},
            allowedContextDirectories: {r'C:\Data7\Contextos'},
          ),
        ),
        definitionVersion: 3,
        definitionSnapshotHash: 'definition-hash',
        createdAt: DateTime.utc(2026, 5, 15),
        updatedAt: DateTime.utc(2026, 5, 15, 1),
      );

      final saveResult = await repository.saveDefinition(definition);
      final loadResult = await repository.getDefinition('action-1');

      expect(saveResult.isSuccess(), isTrue);
      final loaded = loadResult.getOrThrow();
      expect(loaded.id, definition.id);
      expect(loaded.type, AgentActionType.developer);
      expect(loaded.state, AgentActionState.active);
      expect(loaded.policies.remote.canRunSavedAction, isTrue);
      expect(loaded.policies.queue.maxConcurrent, 2);
      expect(loaded.policies.context.allowedContextExtensions, {'.json'});
      expect(loaded.policies.exitCode.acceptedExitCodes, {0, 2});
      expect(loaded.policies.path.allowedWorkingDirectories, {r'C:\Data7'});
      expect(loaded.policies.path.allowedContextDirectories, {
        r'C:\Data7\Contextos',
      });

      final config = loaded.config as DeveloperActionConfig;
      expect(config.connectionId, '34512A51-672C-4ECE-9991-F43E175E7A8B');
      expect(config.connectionLabel, 'Data7');
      expect(config.connectionSnapshotHash, 'hash-redacted');
    });

    test('should roundtrip execution telemetry fields', () async {
      final queueStartedAt = DateTime.utc(2026, 5, 16, 10, 0, 1);
      final execution = AgentActionExecution(
        id: 'telemetry-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.failed,
        requestedAt: DateTime.utc(2026, 5, 16, 10),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-99',
        requestedBy: 'hub-user',
        traceId: 'trace-xyz',
        triggerId: 't-1',
        triggerType: AgentActionTriggerType.remote,
        scheduledAt: DateTime.utc(2026, 5, 16, 9, 59),
        triggeredAt: DateTime.utc(2026, 5, 16, 10, 0, 2),
        queueStartedAt: queueStartedAt,
        processStartedAt: DateTime.utc(2026, 5, 16, 10, 0, 3),
        finishedAt: DateTime.utc(2026, 5, 16, 10, 1),
        exitCode: 1,
        definitionSnapshotHash: 'sha256:def',
        contextHash: 'sha256:ctx',
        redactionApplied: true,
        failureCode: AgentActionFailureCode.exitCodeRejected,
        failurePhase: 'process_exit',
        failureMessage: 'Bad exit.',
      );

      final saveResult = await repository.saveExecution(execution);
      expect(saveResult.isSuccess(), isTrue);

      final listResult = await repository.listExecutions(actionId: 'action-1');
      final loaded = listResult.getOrThrow().singleWhere((e) => e.id == 'telemetry-1');

      expect(loaded.idempotencyKey, 'idem-99');
      expect(loaded.requestedBy, 'hub-user');
      expect(loaded.traceId, 'trace-xyz');
      expect(loaded.triggerId, 't-1');
      expect(loaded.triggerType, AgentActionTriggerType.remote);
      expect(loaded.scheduledAt?.toUtc(), DateTime.utc(2026, 5, 16, 9, 59));
      expect(loaded.triggeredAt?.toUtc(), DateTime.utc(2026, 5, 16, 10, 0, 2));
      expect(loaded.queueStartedAt?.toUtc(), queueStartedAt);
      expect(loaded.definitionSnapshotHash, 'sha256:def');
      expect(loaded.contextHash, 'sha256:ctx');
      expect(loaded.redactionApplied, isTrue);
      expect(loaded.source, AgentActionRequestSource.remoteHub);
      expect(loaded.failureMessage, 'Bad exit.');
    });

    test('should return action not found failure for missing definition', () async {
      final result = await repository.getDefinition('missing');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
    });

    test('should save, list and delete action triggers', () async {
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.weekly,
        name: 'Weekly run',
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 8 * 60,
          weekdays: {1, 3, 5},
          timezoneId: 'America/Cuiaba',
        ),
      );

      final saveResult = await repository.saveTrigger(trigger);
      final getResult = await repository.getTrigger('trigger-1');
      final listResult = await repository.listTriggers(
        actionId: 'action-1',
        isEnabled: true,
        types: {AgentActionTriggerType.weekly},
      );
      final deleteResult = await repository.deleteTrigger('trigger-1');
      final afterDelete = await repository.listTriggers(actionId: 'action-1');

      expect(saveResult.isSuccess(), isTrue);
      final loaded = getResult.getOrThrow();
      expect(loaded.id, 'trigger-1');
      expect(loaded.type, AgentActionTriggerType.weekly);
      expect(loaded.schedule.weekdays, {1, 3, 5});
      expect(loaded.schedule.timezoneId, 'America/Cuiaba');
      expect(listResult.getOrThrow().map((item) => item.id), ['trigger-1']);
      expect(deleteResult.isSuccess(), isTrue);
      expect(afterDelete.getOrThrow(), isEmpty);
    });

    test('should save, list and cleanup executions without removing non-terminal rows', () async {
      final oldFinished = AgentActionExecution(
        id: 'old-finished',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        triggerId: 'trigger-1',
        triggerType: AgentActionTriggerType.daily,
        scheduledAt: DateTime.utc(2026, 5, 10),
        triggeredAt: DateTime.utc(2026, 5, 10, 0, 1),
        finishedAt: DateTime.utc(2026, 5, 10, 1),
        exitCode: 0,
        processExecutable: 'cmd.exe',
        processArgumentCount: 2,
        processCommandPreview: 'cmd.exe /C [REDACTED_COMMAND]',
        stdoutText: 'ok',
        stderrText: '',
        redactionApplied: true,
      );
      final oldRunning = AgentActionExecution(
        id: 'old-running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime.utc(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        processStartedAt: DateTime.utc(2026, 5, 10),
        pid: 1234,
      );
      final oldQueued = AgentActionExecution(
        id: 'old-queued',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime.utc(2026, 5, 10, 1),
      );
      final recentFinished = AgentActionExecution(
        id: 'recent-finished',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.failed,
        requestedAt: DateTime.utc(2026, 5, 14),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime.utc(2026, 5, 14, 1),
        failureCode: AgentActionFailureCode.runtimeError,
        failurePhase: 'process_runtime',
        failureMessage: 'Process failed.',
      );

      await repository.saveExecution(oldFinished);
      await repository.saveExecution(oldRunning);
      await repository.saveExecution(oldQueued);
      await repository.saveExecution(recentFinished);

      final beforeCleanup = await repository.listExecutions(actionId: 'action-1');
      final loadedOldFinished = beforeCleanup.getOrThrow().firstWhere(
        (execution) => execution.id == 'old-finished',
      );
      expect(loadedOldFinished.stdoutText, 'ok');
      expect(loadedOldFinished.triggerId, 'trigger-1');
      expect(loadedOldFinished.triggerType, AgentActionTriggerType.daily);
      expect(loadedOldFinished.scheduledAt?.toUtc(), DateTime.utc(2026, 5, 10));
      expect(loadedOldFinished.processExecutable, 'cmd.exe');
      expect(loadedOldFinished.processArgumentCount, 2);
      expect(loadedOldFinished.processCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
      expect(loadedOldFinished.stdoutTruncated, isFalse);
      final loadedRecentFinished = beforeCleanup.getOrThrow().firstWhere(
        (execution) => execution.id == 'recent-finished',
      );
      expect(loadedRecentFinished.failurePhase, 'process_runtime');
      expect(beforeCleanup.getOrThrow().map((execution) => execution.id), [
        'recent-finished',
        'old-finished',
        'old-queued',
        'old-running',
      ]);

      final cleanupResult = await repository.cleanupExecutions(
        olderThan: DateTime.utc(2026, 5, 12),
      );

      expect(cleanupResult.getOrThrow(), 1);
      final afterCleanup = await repository.listExecutions(actionId: 'action-1');
      expect(afterCleanup.getOrThrow().map((execution) => execution.id), [
        'recent-finished',
        'old-queued',
        'old-running',
      ]);
    });

    test('should spill large stdout to chunks and hydrate on getExecution', () async {
      final largeStdout = 'x' * 20 * 1024;
      expect(AgentActionCapturedOutputChunker.shouldSpillToChunks(largeStdout), isTrue);

      final execution = AgentActionExecution(
        id: 'exec-chunks',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime.utc(2026, 5, 15, 1),
        stdoutText: largeStdout,
        stdoutTruncated: true,
      );

      await repository.saveExecution(execution);

      final listed = await repository.listExecutions(actionId: 'action-1');
      final listedRow = listed.getOrThrow().firstWhere((row) => row.id == 'exec-chunks');
      expect(listedRow.stdoutText, isNull);
      expect(listedRow.stdoutStoredInChunks, isTrue);
      expect(listedRow.stdoutTruncated, isTrue);

      final loaded = await repository.getExecution('exec-chunks');
      expect(loaded.getOrThrow().stdoutText, largeStdout);
      expect(loaded.getOrThrow().stdoutStoredInChunks, isTrue);
    });

    test('should slice spilled stdout without loading full stream on getExecution', () async {
      final largeStdout = 'y' * 20 * 1024;
      final execution = AgentActionExecution(
        id: 'exec-slice',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime.utc(2026, 5, 15, 1),
        stdoutText: largeStdout,
      );

      await repository.saveExecution(execution);

      final withoutHydrate = await repository.getExecution(
        'exec-slice',
        hydrateCapturedOutput: false,
      );
      expect(withoutHydrate.getOrThrow().stdoutText, isNull);
      expect(withoutHydrate.getOrThrow().stdoutStoredInChunks, isTrue);

      final slice = await repository.sliceCapturedOutput(
        executionId: 'exec-slice',
        stream: 'stdout',
        offsetUtf8: 0,
        maxBytes: 64,
      );
      final window = slice.getOrThrow();
      expect(window.text.length, 64);
      expect(window.totalBytes, largeStdout.length);
      expect(window.responseTruncated, isTrue);
      expect(window.nextOffset, 64);
    });

    test('should clear captured output on old terminal executions without deleting rows', () async {
      final oldFinished = AgentActionExecution(
        id: 'old-finished',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime.utc(2026, 5, 10, 1),
        stdoutText: 'ok',
        stderrText: 'warn',
        stdoutTruncated: true,
      );
      final oldRunning = AgentActionExecution(
        id: 'old-running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime.utc(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        stdoutText: 'in progress',
      );
      final recentFinished = AgentActionExecution(
        id: 'recent-finished',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.failed,
        requestedAt: DateTime.utc(2026, 5, 14),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime.utc(2026, 5, 14, 1),
        stdoutText: 'recent',
      );

      await repository.saveExecution(oldFinished);
      await repository.saveExecution(oldRunning);
      await repository.saveExecution(recentFinished);

      final clearResult = await repository.clearCapturedOutputOlderThan(
        olderThan: DateTime.utc(2026, 5, 12),
      );

      expect(clearResult.getOrThrow(), 1);
      final afterClear = await repository.listExecutions(actionId: 'action-1');
      expect(afterClear.getOrThrow().map((execution) => execution.id), [
        'recent-finished',
        'old-finished',
        'old-running',
      ]);
      final cleared = afterClear.getOrThrow().firstWhere(
        (execution) => execution.id == 'old-finished',
      );
      expect(cleared.stdoutText, isNull);
      expect(cleared.stderrText, isNull);
      expect(cleared.stdoutTruncated, isFalse);
      expect(cleared.stderrTruncated, isFalse);
      expect(cleared.stdoutStoredInChunks, isFalse);
      expect(cleared.stderrStoredInChunks, isFalse);
      expect(
        afterClear.getOrThrow().firstWhere((execution) => execution.id == 'recent-finished').stdoutText,
        'recent',
      );
      expect(
        afterClear.getOrThrow().firstWhere((execution) => execution.id == 'old-running').stdoutText,
        'in progress',
      );
    });

    test('should filter executions by status for bootstrap reconciliation', () async {
      final queued = AgentActionExecution(
        id: 'queued',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
      );
      final running = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime.utc(2026, 5, 15, 9, 1),
        source: AgentActionRequestSource.scheduler,
        processStartedAt: DateTime.utc(2026, 5, 15, 9, 1),
        pid: 1234,
      );
      final succeeded = AgentActionExecution(
        id: 'succeeded',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15, 9, 2),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime.utc(2026, 5, 15, 9, 3),
      );

      await repository.saveExecution(queued);
      await repository.saveExecution(running);
      await repository.saveExecution(succeeded);

      final result = await repository.listExecutions(
        statuses: {
          AgentActionExecutionStatus.queued,
          AgentActionExecutionStatus.running,
        },
      );

      expect(result.getOrThrow().map((execution) => execution.id), [
        'running',
        'queued',
      ]);
    });

    test('should filter executions by idempotency key', () async {
      final first = AgentActionExecution(
        id: 'first',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'same-key',
        finishedAt: DateTime.utc(2026, 5, 15, 9, 1),
      );
      final second = AgentActionExecution(
        id: 'second',
        actionId: 'action-2',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15, 9, 2),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'same-key',
        finishedAt: DateTime.utc(2026, 5, 15, 9, 3),
      );
      final unrelated = AgentActionExecution(
        id: 'unrelated',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15, 9, 4),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'other-key',
        finishedAt: DateTime.utc(2026, 5, 15, 9, 5),
      );

      await repository.saveExecution(first);
      await repository.saveExecution(second);
      await repository.saveExecution(unrelated);

      final result = await repository.listExecutions(
        actionId: 'action-1',
        idempotencyKey: 'same-key',
        limit: 1,
      );

      expect(result.getOrThrow().map((execution) => execution.id), ['first']);
    });

    test('should filter executions by requested date window', () async {
      final oldExecution = AgentActionExecution(
        id: 'old',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 10, 9),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime.utc(2026, 5, 10, 9, 1),
      );
      final recentExecution = AgentActionExecution(
        id: 'recent',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime.utc(2026, 5, 15, 9, 1),
      );

      await repository.saveExecution(oldExecution);
      await repository.saveExecution(recentExecution);

      final result = await repository.listExecutions(
        actionId: 'action-1',
        requestedAfter: DateTime.utc(2026, 5, 12),
      );

      expect(result.getOrThrow().map((execution) => execution.id), ['recent']);
    });

    test('should delete triggers when deleting action definition', () async {
      await repository.saveDefinition(
        const AgentActionDefinition(
          id: 'action-del',
          name: 'To delete',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
        ),
      );
      await repository.saveTrigger(
        const AgentActionTrigger(
          id: 'trigger-del',
          actionId: 'action-del',
          type: AgentActionTriggerType.daily,
          schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 8 * 60),
        ),
      );

      final deleteResult = await repository.deleteDefinition('action-del');
      final triggersAfter = await repository.listTriggers(actionId: 'action-del');
      final definitionAfter = await repository.getDefinition('action-del');

      expect(deleteResult.isSuccess(), isTrue);
      expect(triggersAfter.getOrThrow(), isEmpty);
      expect(definitionAfter.isError(), isTrue);
    });

    test('should return not found when deleting missing action definition', () async {
      final deleteResult = await repository.deleteDefinition('missing-action');

      expect(deleteResult.isError(), isTrue);
      expect(deleteResult.exceptionOrNull(), isA<ActionNotFoundFailure>());
    });

    test('should round-trip lifecycle onAppExit policy', () async {
      const definition = AgentActionDefinition(
        id: 'action-lifecycle',
        name: 'Lifecycle',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          lifecycle: AgentActionLifecyclePolicy(
            onAppExit: AgentActionOnAppExitBehavior.leaveRunning,
            waitBeforeKillOnAppExit: Duration(seconds: 10),
          ),
        ),
      );

      await repository.saveDefinition(definition);
      final loaded = await repository.getDefinition('action-lifecycle');

      expect(loaded.getOrThrow().policies.lifecycle.onAppExit, AgentActionOnAppExitBehavior.leaveRunning);
      expect(loaded.getOrThrow().policies.lifecycle.waitBeforeKillOnAppExit, const Duration(seconds: 10));
    });

    test('should round-trip remote policy approval fields', () async {
      final approvedAt = DateTime.utc(2026, 5, 19, 12);
      final definition = AgentActionDefinition(
        id: 'action-remote',
        name: 'Remote',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            allowAdHoc: true,
            approvedBy: 'local-ui',
            approvedAt: approvedAt,
          ),
        ),
      );

      await repository.saveDefinition(definition);
      final loaded = await repository.getDefinition('action-remote');

      final remote = loaded.getOrThrow().policies.remote;
      expect(remote.isEnabled, isTrue);
      expect(remote.allowAdHoc, isTrue);
      expect(remote.approvedBy, 'local-ui');
      expect(remote.approvedAt, approvedAt);
      expect(remote.canRunSavedAction, isTrue);
    });

    test('should round-trip environment allowedProfiles policy', () async {
      const definition = AgentActionDefinition(
        id: 'action-environment',
        name: 'Environment',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          environment: AgentActionEnvironmentPolicy(
            allowedProfiles: {'prod', 'homolog'},
          ),
          exitCode: AgentActionExitCodePolicy(acceptedExitCodes: {0, 1}),
        ),
      );

      await repository.saveDefinition(definition);
      final loaded = await repository.getDefinition('action-environment');

      expect(loaded.getOrThrow().policies.environment.allowedProfiles, {'prod', 'homolog'});
      expect(loaded.getOrThrow().policies.exitCode.acceptedExitCodes, {0, 1});
    });

    test('should load successExitCodes alias when acceptedExitCodes is absent in JSON', () async {
      const mapper = AgentActionDriftMapper();
      final definition = mapper.definitionFromData(
        AgentActionDefinitionData(
          id: 'action-exit-alias',
          name: 'Exit alias',
          type: AgentActionType.commandLine.name,
          state: AgentActionState.active.name,
          configJson: '{"command":"dir"}',
          policiesJson: '{"exitCode":{"successExitCodes":[0,2]}}',
          definitionVersion: 1,
          definitionSnapshotHash: 'hash',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      expect(definition.policies.exitCode.acceptedExitCodes, {0, 2});
    });

    test('should round-trip encoding policy in policies JSON', () {
      const mapper = AgentActionDriftMapper();
      const original = AgentActionDefinition(
        id: 'action-encoding',
        name: 'Encoding policy',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          encoding: AgentActionEncodingPolicy(
            stdout: AgentActionOutputEncodingMode.utf8,
            stderr: AgentActionOutputEncodingMode.utf8,
          ),
        ),
      );

      final roundTripped = mapper.definitionFromData(
        mapper.definitionToData(original, now: DateTime.utc(2026, 5, 18)),
      );

      expect(roundTripped.policies.encoding.stdout, AgentActionOutputEncodingMode.utf8);
      expect(roundTripped.policies.encoding.stderr, AgentActionOutputEncodingMode.utf8);
    });
  });
}
