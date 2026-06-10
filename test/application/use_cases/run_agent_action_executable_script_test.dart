import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _FakeAgentActionRepository implements IAgentActionRepository {
  final Map<String, AgentActionDefinition> definitions = {};
  final Map<String, AgentActionExecution> executions = {};
  final List<AgentActionExecution> savedExecutions = [];

  @override
  Future<Result<AgentActionDefinition>> saveDefinition(
    AgentActionDefinition definition,
  ) async {
    definitions[definition.id] = definition;
    return Success(definition);
  }

  @override
  Future<Result<AgentActionDefinition>> getDefinition(String id) async {
    final definition = definitions[id];
    if (definition == null) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action definition was not found.',
          context: {
            'action_id': id,
            'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
          },
        ),
      );
    }

    return Success(definition);
  }

  @override
  Future<Result<List<AgentActionDefinition>>> listDefinitions() async {
    return Success(definitions.values.toList(growable: false));
  }

  @override
  Future<Result<void>> deleteDefinition(String id) async {
    definitions.remove(id);
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionTrigger>> saveTrigger(AgentActionTrigger trigger) async {
    return Success(trigger);
  }

  @override
  Future<Result<AgentActionTrigger>> getTrigger(String id) async {
    return Failure(ActionNotFoundFailure('Action trigger was not found.'));
  }

  @override
  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async {
    return const Success(<AgentActionTrigger>[]);
  }

  @override
  Future<Result<void>> deleteTrigger(String id) async {
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionExecution>> saveExecution(
    AgentActionExecution execution,
  ) async {
    savedExecutions.add(execution);
    executions[execution.id] = execution;
    return Success(execution);
  }

  @override
  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async {
    final execution = executions[id];
    if (execution == null) {
      return Failure(ActionNotFoundFailure('Action execution was not found.'));
    }

    return Success(execution);
  }

  @override
  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) async {
    return Success(
      (
        text: '',
        nextOffset: offsetUtf8,
        totalBytes: 0,
        responseTruncated: false,
        effectiveStart: offsetUtf8,
      ),
    );
  }

  @override
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    final filtered = executions.values
        .where((execution) {
          final matchesAction = actionId == null || execution.actionId == actionId;
          final matchesIdempotencyKey = idempotencyKey == null || execution.idempotencyKey == idempotencyKey;
          return matchesAction && matchesIdempotencyKey;
        })
        .toList(growable: false);

    return Success(
      limit == null ? filtered : filtered.take(limit).toList(growable: false),
    );
  }

  @override
  Future<Result<int>> cleanupExecutions({required DateTime olderThan}) async {
    return const Success(0);
  }

  @override
  Future<Result<int>> clearCapturedOutputOlderThan({required DateTime olderThan}) async {
    return const Success(0);
  }
}

class _TypedFakeAgentActionLocalRunner implements AgentActionLocalRunner {
  _TypedFakeAgentActionLocalRunner({
    required this.type,
    required this.result,
  });

  @override
  final AgentActionType type;
  final Result<AgentActionProcessResult> result;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return result;
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: expectedPid,
        message: 'Processo principal finalizado.',
      ),
    );
  }
}

class _FakeExecutableActionAdapter implements AgentActionAdapter {
  const _FakeExecutableActionAdapter({
    this.prepareResult,
  });

  final Result<AgentActionPreparedExecution>? prepareResult;

  @override
  AgentActionType get type => AgentActionType.executable;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return prepareResult ??
        Success(
          AgentActionPreparedExecution(
            actionType: type,
            redactedCommandPreview: r'C:\Tools\job.exe --mode ***',
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

class _FakeScriptActionAdapter implements AgentActionAdapter {
  const _FakeScriptActionAdapter();

  @override
  AgentActionType get type => AgentActionType.script;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
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
        redactedCommandPreview: 'powershell.exe -File ***',
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

AgentActionProcessResult _succeededProcessResult() {
  return AgentActionProcessResult(
    status: AgentActionExecutionStatus.succeeded,
    pid: 4321,
    exitCode: 0,
    processStartedAt: DateTime(2026, 5, 15, 10),
    finishedAt: DateTime(2026, 5, 15, 10, 1),
    stdout: AgentActionCapturedOutput.disabled,
    stderr: AgentActionCapturedOutput.disabled,
    redactionApplied: true,
  );
}

void main() {
  late _FakeAgentActionRepository repository;

  setUp(() {
    repository = _FakeAgentActionRepository();
  });

  group('RunAgentActionLocally executable and script', () {
    test('should run executable action and persist terminal execution', () async {
      repository.definitions['exec-1'] = const AgentActionDefinition(
        id: 'exec-1',
        name: 'Run job',
        state: AgentActionState.active,
        config: ExecutableActionConfig(
          executablePath: AgentActionPathReference(
            originalPath: r'C:\Tools\job.exe',
          ),
          arguments: <String>['--mode', 'daily'],
        ),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.executable,
            result: Success(_succeededProcessResult()),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'exec-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.actionType, AgentActionType.executable);
      expect(execution.status, AgentActionExecutionStatus.succeeded);
      expect(repository.savedExecutions, hasLength(3));
      expect(repository.savedExecutions.last.status, AgentActionExecutionStatus.succeeded);
    });

    test('should run script action and persist terminal execution', () async {
      repository.definitions['script-1'] = const AgentActionDefinition(
        id: 'script-1',
        name: 'Run script',
        state: AgentActionState.active,
        config: ScriptActionConfig(
          scriptPath: AgentActionPathReference(
            originalPath: r'C:\Jobs\backup.ps1',
          ),
        ),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.script,
            result: Success(_succeededProcessResult()),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'script-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.actionType, AgentActionType.script);
      expect(execution.status, AgentActionExecutionStatus.succeeded);
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should persist typed failure when executable runner fails', () async {
      repository.definitions['exec-1'] = const AgentActionDefinition(
        id: 'exec-1',
        name: 'Run job',
        state: AgentActionState.active,
        config: ExecutableActionConfig(
          executablePath: AgentActionPathReference(
            originalPath: r'C:\Tools\job.exe',
          ),
        ),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.executable,
            result: Failure(
              ActionRuntimeFailure.withContext(
                message: 'Failed to start executable action process.',
                code: AgentActionFailureCode.runtimeError,
                context: const {
                  'executable': r'C:\Tools\job.exe',
                  'phase': 'start_process',
                },
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'exec-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.failureCode, AgentActionFailureCode.runtimeError);
      expect(execution.failurePhase, 'start_process');
      expect(execution.failureMessage, 'Failed to start executable action process.');
      expect(execution.processExecutable, r'C:\Tools\job.exe');
    });

    test('should persist typed failure when script runner fails', () async {
      repository.definitions['script-1'] = const AgentActionDefinition(
        id: 'script-1',
        name: 'Run script',
        state: AgentActionState.active,
        config: ScriptActionConfig(
          scriptPath: AgentActionPathReference(
            originalPath: r'C:\Jobs\backup.ps1',
          ),
        ),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.script,
            result: Failure(
              ActionRuntimeFailure.withContext(
                message: 'Failed to start script action process.',
                code: AgentActionFailureCode.runtimeError,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'script-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.failureCode, AgentActionFailureCode.runtimeError);
      expect(execution.failurePhase, 'process_runtime');
      expect(execution.failureMessage, 'Failed to start script action process.');
    });

    test('should validate remote executable run via adapter without persisting execution', () async {
      repository.definitions['exec-remote'] = AgentActionDefinition(
        id: 'exec-remote',
        name: 'Remote job',
        state: AgentActionState.active,
        definitionSnapshotHash: 'snap-exec-remote',
        config: const ExecutableActionConfig(
          executablePath: AgentActionPathReference(
            originalPath: r'C:\Tools\job.exe',
          ),
        ),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.executable,
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        adapterRegistry: AgentActionAdapterRegistry([
          const _FakeExecutableActionAdapter(),
        ]),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'exec-remote',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-exec-key-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final summary = result.getOrThrow();
      expect(summary.actionId, 'exec-remote');
      expect(summary.actionType, AgentActionType.executable);
      expect(summary.definitionSnapshotHash, 'snap-exec-remote');
      expect(summary.wouldReplayExistingExecution, isFalse);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should surface adapter prepare failure on validateRemoteRun for executable', () async {
      repository.definitions['exec-remote'] = AgentActionDefinition(
        id: 'exec-remote',
        name: 'Remote job',
        state: AgentActionState.active,
        config: const ExecutableActionConfig(
          executablePath: AgentActionPathReference(
            originalPath: r'C:\Tools\job.exe',
          ),
        ),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.executable,
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        adapterRegistry: AgentActionAdapterRegistry([
          _FakeExecutableActionAdapter(
            prepareResult: Failure(
              ActionValidationFailure.withContext(
                message: 'Executable path is not allowed for remote validation.',
                code: AgentActionFailureCode.executableNotFound,
              ),
            ),
          ),
        ]),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'exec-remote',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-exec-key-2',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).code, AgentActionFailureCode.executableNotFound);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should validate remote script run via adapter without persisting execution', () async {
      repository.definitions['script-remote'] = AgentActionDefinition(
        id: 'script-remote',
        name: 'Remote script',
        state: AgentActionState.active,
        definitionSnapshotHash: 'snap-script-remote',
        config: const ScriptActionConfig(
          scriptPath: AgentActionPathReference(
            originalPath: r'C:\Jobs\backup.ps1',
          ),
        ),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          _TypedFakeAgentActionLocalRunner(
            type: AgentActionType.script,
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        adapterRegistry: AgentActionAdapterRegistry([
          const _FakeScriptActionAdapter(),
        ]),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'script-remote',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-script-key-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final summary = result.getOrThrow();
      expect(summary.actionId, 'script-remote');
      expect(summary.actionType, AgentActionType.script);
      expect(summary.definitionSnapshotHash, 'snap-script-remote');
      expect(repository.savedExecutions, isEmpty);
    });
  });
}
