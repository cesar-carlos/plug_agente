import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

class FakeCommandLineActionAdapter implements AgentActionAdapter {
  const FakeCommandLineActionAdapter();

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
        safeMessage: 'Configuration is valid.',
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: 'cmd.exe /C ***',
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(definition);
  }
}

void main() {
  group('AgentActionExecutionStatusX', () {
    test('should mark only queued and running as non-terminal', () {
      expect(AgentActionExecutionStatus.queued.isTerminal, isFalse);
      expect(AgentActionExecutionStatus.running.isTerminal, isFalse);
      expect(AgentActionExecutionStatus.succeeded.isTerminal, isTrue);
      expect(AgentActionExecutionStatus.failed.isTerminal, isTrue);
      expect(AgentActionExecutionStatus.skipped.isTerminal, isTrue);
      expect(AgentActionExecutionStatus.timedOut.isTerminal, isTrue);
    });
  });

  group('AgentActionContextPolicy', () {
    test('should accept txt and json extensions by default', () {
      const policy = AgentActionContextPolicy();

      expect(policy.allowsExtension('.txt'), isTrue);
      expect(policy.allowsExtension('json'), isTrue);
      expect(policy.allowsExtension('.bat'), isFalse);
    });

    test('should normalize extension casing before validation', () {
      const policy = AgentActionContextPolicy();

      expect(policy.allowsExtension('.JSON'), isTrue);
    });
  });

  group('AgentActionConfig', () {
    test('should expose discriminated type for every planned action config', () {
      const path = AgentActionPathReference(originalPath: r'C:\Tools\tool.exe');

      final configs = <AgentActionConfig>[
        const CommandLineActionConfig(command: 'dir'),
        const ExecutableActionConfig(executablePath: path),
        const ScriptActionConfig(scriptPath: path),
        const JarActionConfig(jarPath: path),
        const EmailActionConfig(
          smtpProfileId: 'smtp-local',
          from: 'agent@example.com',
          to: ['ops@example.com'],
          subjectTemplate: 'Result',
          bodyTemplate: 'Done',
        ),
        const ComObjectActionConfig(
          progId: 'Data7.Object',
          memberName: 'Execute',
        ),
        DeveloperActionConfig.data7Executor(
          executorPath: path,
          projectPath: const AgentActionPathReference(
            originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
          ),
          data7ConfigPath: const AgentActionPathReference(
            originalPath: r'C:\Data7\bin\Data7.Config',
          ),
          connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
          connectionLabel: 'Data7',
        ),
      ];

      expect(
        configs.map((config) => config.type),
        [
          AgentActionType.commandLine,
          AgentActionType.executable,
          AgentActionType.script,
          AgentActionType.jar,
          AgentActionType.email,
          AgentActionType.comObject,
          AgentActionType.developer,
        ],
      );
    });
  });

  group('AgentActionRemotePolicy', () {
    test('should require explicit approval before saved remote execution', () {
      const disabled = AgentActionRemotePolicy(isEnabled: true);
      final approved = AgentActionRemotePolicy(
        isEnabled: true,
        approvedAt: DateTime(2026),
        approvedBy: 'local-user',
      );
      final reapprovalRequired = AgentActionRemotePolicy(
        isEnabled: true,
        approvedAt: DateTime(2026),
        approvedBy: 'local-user',
        requiresReapproval: true,
      );

      expect(disabled.canRunSavedAction, isFalse);
      expect(approved.canRunSavedAction, isTrue);
      expect(reapprovalRequired.canRunSavedAction, isFalse);
    });
  });

  group('AgentActionAdapterRegistry', () {
    test('should resolve registered adapter by type', () {
      final registry = AgentActionAdapterRegistry([
        const FakeCommandLineActionAdapter(),
      ]);

      final result = registry.resolve(AgentActionType.commandLine);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().type, AgentActionType.commandLine);
    });

    test('should return validation failure for unsupported type', () {
      final registry = AgentActionAdapterRegistry([
        const FakeCommandLineActionAdapter(),
      ]);

      final result = registry.resolve(AgentActionType.developer);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should reject duplicate adapters at construction time', () {
      expect(
        () => AgentActionAdapterRegistry([
          const FakeCommandLineActionAdapter(),
          const FakeCommandLineActionAdapter(),
        ]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AgentActionExecution', () {
    test('should expose timeout, skipped, cancelled and killed helpers', () {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.timedOut,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.scheduler,
      );

      expect(execution.timedOut, isTrue);
      expect(execution.skipped, isFalse);
      expect(execution.cancelled, isFalse);
      expect(execution.killed, isFalse);
      expect(execution.isTerminal, isTrue);
    });

    test('should allow copyWith to update definitionSnapshotHash', () {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 16),
        source: AgentActionRequestSource.localUi,
        definitionSnapshotHash: 'sha256:before',
      );

      final updated = execution.copyWith(definitionSnapshotHash: 'sha256:after');

      expect(execution.definitionSnapshotHash, 'sha256:before');
      expect(updated.definitionSnapshotHash, 'sha256:after');
    });

    test('should allow copyWith to update idempotency and trace metadata', () {
      final scheduled = DateTime.utc(2026, 5, 16, 9);
      final triggered = DateTime.utc(2026, 5, 16, 9, 1);
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 16, 10),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'old-key',
        requestedBy: 'old-by',
        traceId: 'old-trace',
        triggerId: 'old-trigger',
        triggerType: AgentActionTriggerType.manual,
        scheduledAt: scheduled,
        triggeredAt: triggered,
      );

      final updated = execution.copyWith(
        idempotencyKey: 'new-key',
        requestedBy: 'new-by',
        traceId: 'new-trace',
        triggerId: 'new-trigger',
        triggerType: AgentActionTriggerType.remote,
      );

      expect(execution.idempotencyKey, 'old-key');
      expect(updated.idempotencyKey, 'new-key');
      expect(updated.requestedBy, 'new-by');
      expect(updated.traceId, 'new-trace');
      expect(updated.triggerId, 'new-trigger');
      expect(updated.triggerType, AgentActionTriggerType.remote);
      expect(updated.scheduledAt?.toUtc(), scheduled);
      expect(updated.triggeredAt?.toUtc(), triggered);
    });
  });

  group('AgentActionTrigger', () {
    test('should classify temporal and lifecycle trigger types', () {
      const appStart = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );
      const daily = AgentActionTrigger(
        id: 'trigger-2',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );

      expect(appStart.isLifecycleTrigger, isTrue);
      expect(appStart.isTemporalTrigger, isFalse);
      expect(daily.isLifecycleTrigger, isFalse);
      expect(daily.isTemporalTrigger, isTrue);
      expect(daily.schedule.hasTimeOfDay, isTrue);
    });
  });
}
