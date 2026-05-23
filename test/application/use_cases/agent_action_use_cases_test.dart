import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
import 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_queue_constants.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

Future<Result<AgentActionDefinition>> saveDefinitionForTest(
  SaveAgentActionDefinition useCase,
  AgentActionDefinition definition,
) async {
  if (definition.state != AgentActionState.active) {
    return useCase(definition);
  }

  final staged = await useCase(
    definition.copyWith(state: AgentActionState.needsValidation),
  );
  if (staged.isError()) {
    return staged;
  }

  final saved = staged.getOrThrow();
  const snapshotter = AgentActionDefinitionSnapshotter();
  final preflightHash = snapshotter.snapshotHash(
    saved.copyWith(state: AgentActionState.needsValidation),
  );
  return useCase(
    saved.copyWith(
      state: AgentActionState.active,
      lastPreflightSnapshotHash: preflightHash,
    ),
  );
}

class FakeCommandLineActionAdapter implements AgentActionAdapter {
  const FakeCommandLineActionAdapter({
    this.normalizedDefinitionFactory,
  });

  final AgentActionDefinition Function(AgentActionDefinition definition)? normalizedDefinitionFactory;

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
    return Success(
      normalizedDefinitionFactory?.call(definition) ?? definition,
    );
  }
}

class FakeAgentActionRepository implements IAgentActionRepository {
  final Map<String, AgentActionDefinition> definitions = {};
  final Map<String, AgentActionTrigger> triggers = {};
  final Map<String, AgentActionExecution> executions = {};
  final List<AgentActionExecution> savedExecutions = [];
  DateTime? lastCleanupOlderThan;
  DateTime? lastClearCapturedOutputOlderThan;

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
    if (!definitions.containsKey(id)) {
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

    definitions.remove(id);
    triggers.removeWhere((_, AgentActionTrigger trigger) => trigger.actionId == id);
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionTrigger>> saveTrigger(
    AgentActionTrigger trigger,
  ) async {
    triggers[trigger.id] = trigger;
    return Success(trigger);
  }

  @override
  Future<Result<AgentActionTrigger>> getTrigger(String id) async {
    final trigger = triggers[id];
    if (trigger == null) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action trigger was not found.',
          context: {
            'trigger_id': id,
            'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
          },
        ),
      );
    }

    return Success(trigger);
  }

  @override
  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async {
    final filtered = triggers.values
        .where((trigger) {
          final matchesAction = actionId == null || trigger.actionId == actionId;
          final matchesEnabled = isEnabled == null || trigger.isEnabled == isEnabled;
          final matchesType = types == null || types.isEmpty || types.contains(trigger.type);
          return matchesAction && matchesEnabled && matchesType;
        })
        .toList(growable: false);

    return Success(filtered);
  }

  @override
  Future<Result<void>> deleteTrigger(String id) async {
    if (!triggers.containsKey(id)) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action trigger was not found.',
          context: {
            'trigger_id': id,
            'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
          },
        ),
      );
    }

    triggers.remove(id);
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
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action execution was not found.',
          context: {
            'execution_id': id,
            'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
          },
        ),
      );
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
          final matchesStatus = statuses == null || statuses.isEmpty || statuses.contains(execution.status);
          final matchesRequestedAfter = requestedAfter == null || !execution.requestedAt.isBefore(requestedAfter);
          return matchesAction && matchesIdempotencyKey && matchesStatus && matchesRequestedAfter;
        })
        .toList(growable: false);

    return Success(
      limit == null ? filtered : filtered.take(limit).toList(growable: false),
    );
  }

  @override
  Future<Result<int>> cleanupExecutions({
    required DateTime olderThan,
  }) async {
    lastCleanupOlderThan = olderThan;
    final before = executions.length;
    executions.removeWhere((_, execution) {
      final finishedAt = execution.finishedAt;
      return finishedAt != null && finishedAt.isBefore(olderThan);
    });

    return Success(before - executions.length);
  }

  @override
  Future<Result<int>> clearCapturedOutputOlderThan({
    required DateTime olderThan,
  }) async {
    lastClearCapturedOutputOlderThan = olderThan;
    var cleared = 0;
    for (final id in executions.keys.toList()) {
      final execution = executions[id]!;
      if (!execution.status.isTerminal) {
        continue;
      }
      final finishedAt = execution.finishedAt;
      final requestedAt = execution.requestedAt;
      final isOld =
          (finishedAt != null && finishedAt.isBefore(olderThan)) ||
          (finishedAt == null && requestedAt.isBefore(olderThan));
      if (!isOld) {
        continue;
      }
      if (execution.stdoutText == null && execution.stderrText == null) {
        continue;
      }
      executions[id] = AgentActionExecution(
        id: execution.id,
        actionId: execution.actionId,
        actionType: execution.actionType,
        status: execution.status,
        requestedAt: execution.requestedAt,
        source: execution.source,
        idempotencyKey: execution.idempotencyKey,
        requestedBy: execution.requestedBy,
        traceId: execution.traceId,
        runtimeInstanceId: execution.runtimeInstanceId,
        runtimeSessionId: execution.runtimeSessionId,
        triggerId: execution.triggerId,
        triggerType: execution.triggerType,
        scheduledAt: execution.scheduledAt,
        triggeredAt: execution.triggeredAt,
        queueStartedAt: execution.queueStartedAt,
        processStartedAt: execution.processStartedAt,
        finishedAt: execution.finishedAt,
        timeoutAt: execution.timeoutAt,
        pid: execution.pid,
        exitCode: execution.exitCode,
        processExecutable: execution.processExecutable,
        processArgumentCount: execution.processArgumentCount,
        processCommandPreview: execution.processCommandPreview,
        definitionSnapshotHash: execution.definitionSnapshotHash,
        contextHash: execution.contextHash,
        redactionApplied: execution.redactionApplied,
        failureCode: execution.failureCode,
        failurePhase: execution.failurePhase,
        failureMessage: execution.failureMessage,
      );
      cleared++;
    }
    return Success(cleared);
  }
}

class CountingSaveAgentActionExecution extends SaveAgentActionExecution {
  CountingSaveAgentActionExecution(super.repository);

  int invocationCount = 0;

  @override
  Future<Result<AgentActionExecution>> call(AgentActionExecution execution) async {
    invocationCount++;
    return super.call(execution);
  }
}

class FakeElevatedActionExecutionCanceller implements IElevatedActionExecutionCanceller {
  FakeElevatedActionExecutionCanceller({required this.cancelResult});

  final Result<AgentActionCancellationResult> cancelResult;
  String? lastExecutionId;

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
  }) async {
    lastExecutionId = executionId;
    return cancelResult;
  }
}

class FakeAgentActionLocalRunner implements AgentActionLocalRunner {
  FakeAgentActionLocalRunner({
    required this.result,
    Result<AgentActionCancellationResult>? cancelResult,
  }) : cancelResult =
           cancelResult ??
           const Success(
             AgentActionCancellationResult(
               executionId: 'execution-1',
               status: AgentActionExecutionStatus.killed,
               killed: true,
               pid: 1234,
               message: 'Processo principal finalizado.',
             ),
           );

  final Result<AgentActionProcessResult> result;
  final Result<AgentActionCancellationResult> cancelResult;
  int? lastExpectedPid;
  String? lastExpectedProcessExecutable;
  DateTime? lastExpectedProcessStartedAt;
  int cancelInvocationCount = 0;

  @override
  AgentActionType get type => AgentActionType.commandLine;

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
    cancelInvocationCount++;
    lastExpectedPid = expectedPid;
    lastExpectedProcessExecutable = expectedProcessExecutable;
    lastExpectedProcessStartedAt = expectedProcessStartedAt;
    return cancelResult;
  }
}

class RetryThenSucceedAgentActionLocalRunner implements AgentActionLocalRunner {
  int callCount = 0;

  @override
  AgentActionType get type => AgentActionType.commandLine;

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

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    callCount++;
    if (callCount == 1) {
      return Success(
        AgentActionProcessResult(
          status: AgentActionExecutionStatus.failed,
          pid: 1111,
          exitCode: 1,
          processStartedAt: DateTime(2026, 5, 15, 10),
          finishedAt: DateTime(2026, 5, 15, 10),
          stdout: AgentActionCapturedOutput.disabled,
          stderr: AgentActionCapturedOutput.disabled,
          redactionApplied: true,
        ),
      );
    }

    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 4321,
        exitCode: 0,
        processStartedAt: DateTime(2026, 5, 15, 10, 1),
        finishedAt: DateTime(2026, 5, 15, 10, 2),
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }
}

class ControlledAgentActionLocalRunner implements AgentActionLocalRunner {
  final List<Completer<Result<AgentActionProcessResult>>> completions = <Completer<Result<AgentActionProcessResult>>>[];
  final List<Completer<void>> starts = <Completer<void>>[];

  int get startedCount => starts.length;

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    final started = Completer<void>();
    starts.add(started);
    started.complete();

    final completion = Completer<Result<AgentActionProcessResult>>();
    completions.add(completion);
    return completion.future;
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
        pid: 4321,
        message: 'Processo principal finalizado.',
      ),
    );
  }
}

void main() {
  late FakeAgentActionRepository repository;
  late ValidateAgentActionDefinition validateDefinition;
  late FeatureFlags featureFlags;

  setUp(() {
    repository = FakeAgentActionRepository();
    featureFlags = FeatureFlags(InMemoryAppSettingsStore());
    validateDefinition = ValidateAgentActionDefinition(
      AgentActionAdapterRegistry([
        const FakeCommandLineActionAdapter(),
      ]),
    );
  });

  group('agent action definition use cases', () {
    test('should save valid definition after adapter validation', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      final saved = repository.definitions['action-1']!;
      expect(saved.definitionSnapshotHash, startsWith('sha256:'));
      expect(result.getOrThrow().definitionSnapshotHash, saved.definitionSnapshotHash);
    });

    test('should reject saving active definition without successful preflight', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await useCase(definition);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect((result.exceptionOrNull()! as ActionValidationFailure).code, AgentActionFailureCode.preflightRequiredForActive);
      expect(repository.definitions, isEmpty);
    });

    test('should allow saving active definition after preflight hash is recorded', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().state, AgentActionState.active);
      expect(result.getOrThrow().lastPreflightSnapshotHash, isNotNull);
    });

    test('should invalidate preflight hash when definition content changes on save', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final first = await saveDefinitionForTest(useCase, definition);
      expect(first.isSuccess(), isTrue);

      final activeWithoutPreflight = await useCase(
        first.getOrThrow().copyWith(
          config: const CommandLineActionConfig(command: 'dir /b'),
          lastPreflightSnapshotHash: first.getOrThrow().lastPreflightSnapshotHash,
        ),
      );

      expect(activeWithoutPreflight.isError(), isTrue);
      expect((activeWithoutPreflight.exceptionOrNull()! as ActionValidationFailure).code, AgentActionFailureCode.preflightRequiredForActive);
    });

    test('should clear runElevated when elevated feature flag is disabled', () async {
      await featureFlags.setEnableElevatedAgentActions(false);
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: 'action-elevated',
        name: 'Elevated action',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().policies.elevated.runElevated, isFalse);
    });

    test('should require remote reapproval on save when secret reference fingerprint changes', () async {
      final secretStore = _InMemoryAgentActionSecretStoreForRunTests();
      await secretStore.saveSecret('api', 'v1');
      const snapshotter = AgentActionDefinitionSnapshotter();
      final fingerprinter = AgentActionSecretReferenceFingerprinter(secretStore);
      const base = AgentActionDefinition(
        id: 'action-secret',
        name: 'Secret cmd',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api}'),
      );
      final approvedAt = DateTime.utc(2026, 5, 20, 9);
      final initialFingerprints = await fingerprinter.fingerprintsFor(base);
      final preflightHash = snapshotter.snapshotHash(
        base.copyWith(state: AgentActionState.needsValidation),
      );
      repository.definitions['action-secret'] = base.copyWith(
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
            riskFingerprint: snapshotter.riskFingerprint(
              base,
              secretReferenceFingerprints: initialFingerprints,
            ),
          ),
        ),
        lastPreflightSnapshotHash: preflightHash,
      );

      await secretStore.saveSecret('api', 'v2');
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        snapshotter,
        featureFlags,
        secretReferenceFingerprinter: fingerprinter,
      );
      final result = await useCase(
        base.copyWith(
          state: AgentActionState.needsValidation,
          lastPreflightSnapshotHash: null,
          policies: AgentActionDefinitionPolicies(
            remote: AgentActionRemotePolicy(
              isEnabled: true,
              approvedAt: approvedAt,
              approvedBy: 'local-ui',
            ),
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().policies.remote.requiresReapproval, isTrue);
      expect(result.getOrThrow().policies.remote.canRunSavedAction, isFalse);
    });

    test('should clear allowAdHoc when remote ad-hoc feature flag is disabled', () async {
      await featureFlags.setEnableRemoteAdHocAgentActions(false);
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      final definition = AgentActionDefinition(
        id: 'action-adhoc',
        name: 'Remote ad-hoc',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            allowAdHoc: true,
            approvedAt: DateTime.utc(2026, 5, 19),
            approvedBy: 'local-ui',
          ),
        ),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().policies.remote.allowAdHoc, isFalse);
    });

    test('should trim definition id and name when saving', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const definition = AgentActionDefinition(
        id: '  action-x  ',
        name: '  Run  ',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'action-x');
      expect(result.getOrThrow().name, 'Run');
      expect(repository.definitions['action-x'], isNotNull);
      expect(repository.definitions.containsKey('  action-x  '), isFalse);
    });

    test('should reject saving remote-approved definition when app-close trigger exists', () async {
      repository.triggers['t1'] = const AgentActionTrigger(
        id: 't1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      final definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
          ),
        ),
      );

      final result = await useCase(definition);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.definitions, isEmpty);
    });

    test('should save remote-enabled definition when app-close exists but reapproval is required', () async {
      repository.triggers['t1'] = const AgentActionTrigger(
        id: 't1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      final definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
            requiresReapproval: true,
          ),
        ),
      );

      final result = await saveDefinitionForTest(useCase, definition);

      expect(result.isSuccess(), isTrue);
      expect(repository.definitions['action-1'], isNotNull);
    });

    test('should not save invalid definition', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );

      final result = await useCase(
        const AgentActionDefinition(
          id: 'action-1',
          name: '',
          config: CommandLineActionConfig(command: 'dir'),
        ),
      );

      expect(result.isError(), isTrue);
      expect(repository.definitions, isEmpty);
    });

    test('should require remote reapproval when risk fingerprint changes on save', () async {
      const snapshotter = AgentActionDefinitionSnapshotter();
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        snapshotter,
        featureFlags,
      );
      final approvedAt = DateTime.utc(2026, 5, 19, 10);
      final initial = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
          ),
        ),
      );

      final first = await saveDefinitionForTest(useCase, initial);
      expect(first.isSuccess(), isTrue);
      expect(first.getOrThrow().policies.remote.canRunSavedAction, isTrue);

      final changed = first.getOrThrow().copyWith(
        config: const CommandLineActionConfig(command: 'dir /b'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: approvedAt,
            approvedBy: 'local-ui',
          ),
        ),
        state: AgentActionState.needsValidation,
        lastPreflightSnapshotHash: null,
      );

      final staged = await useCase(changed);
      expect(staged.isSuccess(), isTrue);
      final preflightHash = snapshotter.snapshotHash(
        staged.getOrThrow().copyWith(state: AgentActionState.needsValidation),
      );
      final second = await useCase(
        staged.getOrThrow().copyWith(
          state: AgentActionState.active,
          lastPreflightSnapshotHash: preflightHash,
        ),
      );

      expect(second.isSuccess(), isTrue);
      final remote = second.getOrThrow().policies.remote;
      expect(remote.requiresReapproval, isTrue);
      expect(remote.canRunSavedAction, isFalse);
    });

    test('should change definition snapshot hash when relevant definition fields change', () async {
      final useCase = SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );
      const baseDefinition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      final first = await saveDefinitionForTest(useCase, baseDefinition);
      final second = await saveDefinitionForTest(
        useCase,
        baseDefinition.copyWith(
          config: const CommandLineActionConfig(command: 'dir /b'),
        ),
      );

      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);
      expect(
        first.getOrThrow().definitionSnapshotHash,
        isNot(equals(second.getOrThrow().definitionSnapshotHash)),
      );
    });

    test('should persist normalized path metadata before hashing definition', () async {
      final validatingUseCase = ValidateAgentActionDefinition(
        AgentActionAdapterRegistry([
          FakeCommandLineActionAdapter(
            normalizedDefinitionFactory: (definition) {
              final config = definition.config as CommandLineActionConfig;
              return definition.copyWith(
                config: CommandLineActionConfig(
                  command: config.command,
                  workingDirectory: AgentActionPathReference(
                    originalPath: r'C:\Jobs',
                    canonicalPath: r'C:\Canonical\Jobs',
                    existsAtValidation: true,
                    validatedAt: DateTime.utc(2026, 5, 15, 12),
                  ),
                ),
              );
            },
          ),
        ]),
      );
      final useCase = SaveAgentActionDefinition(
        repository,
        validatingUseCase,
        const AgentActionDefinitionSnapshotter(),
        featureFlags,
      );

      final result = await saveDefinitionForTest(
        useCase,
        const AgentActionDefinition(
          id: 'action-1',
          name: 'Run command',
          state: AgentActionState.active,
          config: CommandLineActionConfig(
            command: 'dir',
            workingDirectory: AgentActionPathReference(
              originalPath: r'C:\Jobs',
            ),
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
      final saved = repository.definitions['action-1']!;
      final config = saved.config as CommandLineActionConfig;
      expect(config.workingDirectory?.canonicalPath, r'C:\Canonical\Jobs');
      expect(config.workingDirectory?.existsAtValidation, isTrue);
      expect(config.workingDirectory?.validatedAt, DateTime.utc(2026, 5, 15, 12));
      expect(saved.definitionSnapshotHash, startsWith('sha256:'));
    });

    test('should get, list and delete definitions through repository', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;

      final getResult = await GetAgentActionDefinition(repository)('action-1');
      final listResult = await ListAgentActionDefinitions(repository)();
      final deleteResult = await DeleteAgentActionDefinition(repository)('action-1');

      expect(getResult.getOrThrow(), definition);
      expect(listResult.getOrThrow(), [definition]);
      expect(deleteResult.isSuccess(), isTrue);
      expect(repository.definitions, isEmpty);
    });

    test('should test saved definition without executing action', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;
      final useCase = TestAgentActionDefinition(
        repository,
        validateDefinition,
      );

      final result = await useCase('action-1');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().actionType, AgentActionType.commandLine);
      expect(result.getOrThrow().canRun, isTrue);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject test definition with empty action id', () async {
      final useCase = TestAgentActionDefinition(
        repository,
        validateDefinition,
      );

      final result = await useCase(' ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });

    test('should return not found failure when deleting missing definition', () async {
      final result = await DeleteAgentActionDefinition(repository)('missing');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
    });

    test('should reject delete definition with blank id', () async {
      final result = await DeleteAgentActionDefinition(repository)('  \t');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim action id when deleting definition', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;

      final result = await DeleteAgentActionDefinition(repository)('  action-1  ');

      expect(result.isSuccess(), isTrue);
      expect(repository.definitions, isEmpty);
    });

    test('should reject get definition with blank id', () async {
      final result = await GetAgentActionDefinition(repository)('  \t');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim id when getting definition', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.definitions[definition.id] = definition;

      final result = await GetAgentActionDefinition(repository)('  action-1  ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'action-1');
    });
  });

  group('agent action trigger use cases', () {
    setUp(() {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
    });

    test('should reject trigger save when maintenance mode is enabled', () async {
      await featureFlags.setEnableAgentActionsMaintenanceMode(true);
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-maint',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as ActionValidationFailure).code, AgentActionFailureCode.maintenanceMode);
    });

    test('should save valid app start trigger for an existing action', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      final saved = repository.triggers['trigger-1'];
      expect(saved, isNotNull);
      expect(saved!.id, trigger.id);
      expect(saved.actionId, trigger.actionId);
      expect(saved.type, trigger.type);
    });

    test('should trim trigger id and action id when saving trigger', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: '  trigger-spaced  ',
        actionId: '  action-1  ',
        type: AgentActionTriggerType.manual,
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'trigger-spaced');
      expect(result.getOrThrow().actionId, 'action-1');
      expect(repository.triggers['trigger-spaced'], isNotNull);
      expect(repository.triggers['trigger-spaced']!.actionId, 'action-1');
      expect(repository.triggers.containsKey('  trigger-spaced  '), isFalse);
    });

    test('should reject app-close trigger when action is approved for remote execution', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Remote ready',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
          ),
        ),
      );
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should reject app-close trigger when action requires elevated execution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Elevated command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should save app-close trigger when remote policy requires reapproval', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Remote stale',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
            requiresReapproval: true,
          ),
        ),
      );
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      final saved = repository.triggers['trigger-1'];
      expect(saved, isNotNull);
      expect(saved!.id, trigger.id);
      expect(saved.actionId, trigger.actionId);
      expect(saved.type, trigger.type);
    });

    test('should save temporal interval trigger with positive interval', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.interval,
        schedule: AgentActionTriggerSchedule(
          interval: Duration(minutes: 15),
        ),
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().schedule.interval, const Duration(minutes: 15));
    });

    test('should reject invalid weekly trigger before saving', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.weekly,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 8 * 60,
          weekdays: {0},
        ),
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should return not found when trigger references missing action', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'missing-action',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should get, list and delete triggers through repository', () async {
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 9 * 60,
        ),
      );
      repository.triggers[trigger.id] = trigger;

      final getResult = await GetAgentActionTrigger(repository)('trigger-1');
      final listResult = await ListAgentActionTriggers(repository)(
        actionId: 'action-1',
        isEnabled: true,
        types: {AgentActionTriggerType.daily},
      );
      final deleteResult = await DeleteAgentActionTrigger(repository)('trigger-1');

      expect(getResult.getOrThrow(), trigger);
      expect(listResult.getOrThrow(), [trigger]);
      expect(deleteResult.isSuccess(), isTrue);
      expect(repository.triggers, isEmpty);
    });

    test('should reject delete trigger with blank id', () async {
      final result = await DeleteAgentActionTrigger(repository)('   ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should return not found when deleting missing trigger', () async {
      final result = await DeleteAgentActionTrigger(repository)('missing-trigger');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
    });

    test('should reject get trigger with blank id', () async {
      final result = await GetAgentActionTrigger(repository)('');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim id when getting trigger', () async {
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.manual,
      );
      repository.triggers[trigger.id] = trigger;

      final result = await GetAgentActionTrigger(repository)(' trigger-1 ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'trigger-1');
    });

    test('should reject list triggers with blank action id filter', () async {
      final result = await ListAgentActionTriggers(repository)(actionId: '  ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim action id when listing triggers', () async {
      repository.triggers['t1'] = const AgentActionTrigger(
        id: 't1',
        actionId: 'action-1',
        type: AgentActionTriggerType.manual,
      );

      final result = await ListAgentActionTriggers(repository)(actionId: '  action-1  ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), hasLength(1));
    });

    test('should dispatch temporal trigger through local action runner with trigger metadata', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 9 * 60,
        ),
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'trigger-1',
        scheduledAt: DateTime.utc(2026, 5, 15, 13),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.source, AgentActionRequestSource.scheduler);
      expect(execution.triggerId, 'trigger-1');
      expect(execution.triggerType, AgentActionTriggerType.daily);
      expect(execution.scheduledAt, DateTime.utc(2026, 5, 15, 13));
      expect(execution.triggeredAt, DateTime(2026, 5, 15, 9));
      expect(execution.idempotencyKey, 'trigger:trigger-1:2026-05-15T13:00:00.000Z');
    });

    test('should trim trigger action id when dispatching temporal trigger', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: '  action-1  ',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 9 * 60,
        ),
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'trigger-1',
        scheduledAt: DateTime.utc(2026, 5, 15, 13),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().actionId, 'action-1');
    });

    test('should reject dispatch when trigger action id is only whitespace', () async {
      repository.triggers['bad-trigger'] = const AgentActionTrigger(
        id: 'bad-trigger',
        actionId: '   ',
        type: AgentActionTriggerType.manual,
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(repository, runUseCase);

      final result = await dispatchUseCase(triggerId: 'bad-trigger');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).code, AgentActionFailureCode.triggerActionIdBlank);
    });

    test('should dispatch remote trigger through the same local action runner flow', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      repository.triggers['remote-trigger'] = const AgentActionTrigger(
        id: 'remote-trigger',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'remote-trigger',
        idempotencyKey: 'remote-key-1',
        requestedBy: 'hub:user-1',
        traceId: 'trace-1',
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.source, AgentActionRequestSource.remoteHub);
      expect(execution.triggerId, 'remote-trigger');
      expect(execution.triggerType, AgentActionTriggerType.remote);
      expect(execution.requestedBy, 'hub:user-1');
      expect(execution.traceId, 'trace-1');
      expect(execution.idempotencyKey, 'remote-key-1');
      expect(repository.savedExecutions.map((item) => item.status), [
        AgentActionExecutionStatus.queued,
        AgentActionExecutionStatus.running,
        AgentActionExecutionStatus.succeeded,
      ]);
    });

    test('should trim optional metadata when dispatching remote trigger', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      repository.triggers['remote-trigger'] = const AgentActionTrigger(
        id: 'remote-trigger',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'remote-trigger',
        idempotencyKey: '  remote-key-trimmed  ',
        requestedBy: '  hub:user-1  ',
        traceId: '  trace-99  ',
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.requestedBy, 'hub:user-1');
      expect(execution.traceId, 'trace-99');
      expect(execution.idempotencyKey, 'remote-key-trimmed');
    });

    test('should reject dispatch when trigger is disabled', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
        isEnabled: false,
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(repository, runUseCase);

      final result = await dispatchUseCase(triggerId: 'trigger-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });
  });

  group('agent action execution use cases', () {
    test('should save, get and list executions through repository', () async {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
      );

      final saveResult = await SaveAgentActionExecution(repository)(execution);
      final getResult = await GetAgentActionExecution(repository)('execution-1');
      final listResult = await ListAgentActionExecutions(repository)(
        actionId: 'action-1',
        limit: 1,
      );

      expect(saveResult.getOrThrow(), execution);
      expect(getResult.getOrThrow(), execution);
      expect(listResult.getOrThrow(), [execution]);
    });

    test('should reject save execution with blank execution id', () async {
      final execution = AgentActionExecution(
        id: '  ',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
      );

      final result = await SaveAgentActionExecution(repository)(execution);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.executions, isEmpty);
    });

    test('should reject save execution with blank action id', () async {
      final execution = AgentActionExecution(
        id: 'e1',
        actionId: '\t',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
      );

      final result = await SaveAgentActionExecution(repository)(execution);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.executions, isEmpty);
    });

    test('should reject save execution with blank idempotency key when set', () async {
      final execution = AgentActionExecution(
        id: 'e1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: '  ',
      );

      final result = await SaveAgentActionExecution(repository)(execution);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.executions, isEmpty);
    });

    test('should reject get execution with blank id', () async {
      final result = await GetAgentActionExecution(repository)('  ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim id when getting execution', () async {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime(2026),
      );
      repository.executions[execution.id] = execution;

      final result = await GetAgentActionExecution(repository)(' execution-1 ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
    });

    test('should reject list executions with blank action id filter', () async {
      final result = await ListAgentActionExecutions(repository)(actionId: '\t');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should reject list executions with blank idempotency key filter', () async {
      final result = await ListAgentActionExecutions(repository)(idempotencyKey: '  ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim filters when listing executions', () async {
      final execution = AgentActionExecution(
        id: 'e1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'idem-key',
        finishedAt: DateTime(2026),
      );
      repository.executions['e1'] = execution;

      final result = await ListAgentActionExecutions(repository)(
        actionId: '  action-1  ',
        idempotencyKey: ' idem-key ',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), [execution]);
    });

    test('should cleanup executions older than retention window', () async {
      repository.executions['old'] = AgentActionExecution(
        id: 'old',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 10),
      );
      repository.executions['new'] = AgentActionExecution(
        id: 'new',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 14),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 14),
      );

      final result = await CleanupAgentActionExecutions(repository)(
        now: DateTime(2026, 5, 15),
      );

      expect(result.getOrThrow(), 1);
      expect(repository.lastCleanupOlderThan, DateTime(2026, 5, 12));
      expect(repository.executions.keys, ['new']);
    });

    test('should clear captured output older than retention without deleting executions', () async {
      repository.executions['old'] = AgentActionExecution(
        id: 'old',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 10),
        stdoutText: 'stdout blob',
        stderrText: 'stderr blob',
      );
      repository.executions['new'] = AgentActionExecution(
        id: 'new',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 14),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 14),
        stdoutText: 'keep',
      );
      repository.executions['running'] = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        stdoutText: 'still running',
      );

      final result = await CleanupAgentActionCapturedOutput(
        repository,
        retention: const Duration(days: 3),
      )(now: DateTime(2026, 5, 15));

      expect(result.getOrThrow(), 1);
      expect(repository.lastClearCapturedOutputOlderThan, DateTime(2026, 5, 12));
      expect(repository.executions['old']?.stdoutText, isNull);
      expect(repository.executions['old']?.stderrText, isNull);
      expect(repository.executions['new']?.stdoutText, 'keep');
      expect(repository.executions['running']?.stdoutText, 'still running');
    });

    test('should mark queued and running executions as interrupted on bootstrap reconciliation', () async {
      repository.executions['queued'] = AgentActionExecution(
        id: 'queued',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
      );
      repository.executions['running'] = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 1234,
      );
      repository.executions['finished'] = AgentActionExecution(
        id: 'finished',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final useCase = ReconcileAgentActionExecutions(
        repository,
        now: () => DateTime(2026, 5, 15, 10),
      );

      final result = await useCase();
      final secondResult = await useCase();

      expect(result.getOrThrow(), 2);
      expect(secondResult.getOrThrow(), 0);
      expect(repository.executions['queued']?.status, AgentActionExecutionStatus.interrupted);
      expect(repository.executions['running']?.status, AgentActionExecutionStatus.interrupted);
      expect(repository.executions['finished']?.status, AgentActionExecutionStatus.succeeded);
      expect(repository.executions['queued']?.finishedAt, DateTime(2026, 5, 15, 10));
      expect(repository.executions['running']?.failureCode, AgentActionFailureCode.interruptedOnBootstrap);
      expect(repository.executions['running']?.failurePhase, 'bootstrap_reconciliation');
    });

    test('should persist bootstrap reconciliation through SaveAgentActionExecution', () async {
      repository.executions['queued'] = AgentActionExecution(
        id: 'queued',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
      );
      repository.executions['running'] = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 1234,
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final useCase = ReconcileAgentActionExecutions(
        repository,
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 10),
      );

      final result = await useCase();

      expect(result.getOrThrow(), 2);
      expect(countingSave.invocationCount, 2);
    });

    test('should run local action and persist terminal execution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                processExecutable: 'cmd.exe',
                processArgumentCount: 2,
                processCommandPreview: 'cmd.exe /C [REDACTED_COMMAND]',
                stdout: const AgentActionCapturedOutput(
                  text: 'ok',
                  isCaptured: true,
                ),
                stderr: AgentActionCapturedOutput.disabled,
                contextHash: 'sha256:context',
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'key-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(repository.savedExecutions, hasLength(3));
      expect(repository.savedExecutions[0].status, AgentActionExecutionStatus.queued);
      expect(repository.savedExecutions[1].status, AgentActionExecutionStatus.running);
      expect(execution.status, AgentActionExecutionStatus.succeeded);
      expect(execution.pid, 1234);
      expect(execution.processExecutable, 'cmd.exe');
      expect(execution.processArgumentCount, 2);
      expect(execution.processCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
      expect(execution.stdoutText, 'ok');
      expect(execution.contextHash, 'sha256:context');
      expect(execution.idempotencyKey, 'key-1');
    });

    test('should retry local execution when first attempt fails with retriable status', () async {
      repository.definitions['action-retry'] = const AgentActionDefinition(
        id: 'action-retry',
        name: 'Retry command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          retry: AgentActionRetryPolicy(maxAttempts: 2),
        ),
      );
      final runner = RetryThenSucceedAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-retry',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(runner.callCount, 2);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.succeeded);
      expect(result.getOrThrow().exitCode, 0);
    });

    test('should route local run persistence through SaveAgentActionExecution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 9),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'key-1',
        ),
      );

      expect(countingSave.invocationCount, 3);
    });

    test('should persist trimmed idempotency key and optional metadata on local run', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: '  key-1  ',
          requestedBy: '  local-user  ',
          traceId: '  trace-t  ',
          triggerId: '  trig-1  ',
          triggerType: AgentActionTriggerType.manual,
        ),
      );

      final first = repository.savedExecutions.first;
      expect(first.idempotencyKey, 'key-1');
      expect(first.requestedBy, 'local-user');
      expect(first.traceId, 'trace-t');
      expect(first.triggerId, 'trig-1');
    });

    test('should resolve definition when action id has surrounding whitespace', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: '  action-1  ',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().actionId, 'action-1');
    });

    test('should return queued execution immediately when requested', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-key-1',
          returnWhenQueued: true,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final queuedExecution = result.getOrThrow();
      expect(queuedExecution.status, AgentActionExecutionStatus.queued);
      expect(queuedExecution.idempotencyKey, 'remote-key-1');
      await _waitForRunnerStarts(runner, 1);
      expect(repository.executions[queuedExecution.id]?.status, AgentActionExecutionStatus.running);

      final repeatedResult = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-key-1',
          returnWhenQueued: true,
        ),
      );

      expect(repeatedResult.isSuccess(), isTrue);
      expect(repeatedResult.getOrThrow().id, queuedExecution.id);
      expect(repeatedResult.getOrThrow().status, AgentActionExecutionStatus.running);
      expect(runner.startedCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.executions[queuedExecution.id]?.status, AgentActionExecutionStatus.succeeded);
    });

    test('should return validateRemoteRun summary without persisting an execution', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-validate-clean',
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
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-validate-key-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final summary = result.getOrThrow();
      expect(summary.actionId, 'action-1');
      expect(summary.actionType, AgentActionType.commandLine);
      expect(summary.definitionSnapshotHash, 'snap-validate-clean');
      expect(summary.wouldReplayExistingExecution, isFalse);
      expect(summary.existingExecutionId, isNull);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should return wouldReplay from persisted idempotency on validateRemoteRun', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-validate-replay',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      repository.executions['exec-prior'] = AgentActionExecution(
        id: 'exec-prior',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 7),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-replay-1',
        finishedAt: DateTime(2026, 5, 15, 7, 5),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-replay-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final summary = result.getOrThrow();
      expect(summary.wouldReplayExistingExecution, isTrue);
      expect(summary.existingExecutionId, 'exec-prior');
      expect(summary.definitionSnapshotHash, 'snap-validate-replay');
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject validateRemoteRun for remote hub without idempotency key', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
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
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteIdempotencyRequired);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote run with contextPath on validateRemoteRun', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-1',
          contextPath: r'C:\ctx\input.json',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteContextNotSupported);
      expect(
        failure.context['reason'],
        AgentActionRpcConstants.remoteContextNotSupportedRpcReason,
      );
    });

    test('should reject remote run with runtimeParameters', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-ctx-params',
          runtimeParameters: <String, Object?>{'key': 'value'},
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteContextNotSupported);
    });

    test('should append remote lifecycle audit rows for remote hub run', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableAgentActionRemoteAudit(true);
      final auditStore = _MemoryRemoteAuditStore();
      final lifecycleAudit = AgentActionRemoteLifecycleAuditRecorder(
        featureFlags: flags,
        auditStore: auditStore,
        runtimeIdentity: const AgentRuntimeIdentity(
          runtimeInstanceId: 'inst-test',
          runtimeSessionId: 'sess-test',
        ),
        uuid: const Uuid(),
        now: () => DateTime.utc(2026, 5, 18, 12),
      );
      final runner = FakeAgentActionLocalRunner(
        result: Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        featureFlags: flags,
        remoteLifecycleAudit: lifecycleAudit,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'lifecycle-audit-1',
          traceId: 'trace-lifecycle',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final outcomes = auditStore.rows.map((row) => row.outcome).toList();
      expect(
        outcomes,
        containsAll(<String>[
          AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued,
          AgentActionRemoteAuditConstants.outcomeLifecycleStarted,
          AgentActionRemoteAuditConstants.outcomeLifecycleFinished,
        ]),
      );
      expect(auditStore.rows.first.traceId, 'trace-lifecycle');
    });

    test('should treat validateRemoteRun as would replay when same idempotency run is in flight', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-in-flight',
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
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-in-flight',
          returnWhenQueued: true,
        ),
      );
      await _waitForRunnerStarts(runner, 1);

      final validateResult = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-in-flight',
        ),
      );

      expect(validateResult.isSuccess(), isTrue);
      final summary = validateResult.getOrThrow();
      expect(summary.wouldReplayExistingExecution, isTrue);
      expect(summary.existingExecutionId, isNull);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('should persist failed execution when local runner fails', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(
              ActionRuntimeFailure.withContext(
                message: 'Failed to start command line action process.',
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
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.failureCode, AgentActionFailureCode.runtimeError);
      expect(execution.failurePhase, 'process_runtime');
      expect(execution.failureMessage, 'Failed to start command line action process.');
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should persist process metadata from runner failure context', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(
              ActionRuntimeFailure.withContext(
                message: 'Failed to start command line action process.',
                code: AgentActionFailureCode.runtimeError,
                context: const {
                  'executable': 'cmd.exe',
                  'argument_count': 2,
                  'command_preview': 'cmd.exe /C [REDACTED_COMMAND]',
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
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.failurePhase, 'start_process');
      expect(execution.processExecutable, 'cmd.exe');
      expect(execution.processArgumentCount, 2);
      expect(execution.processCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
    });

    test('should persist rejected exit code as actionable execution failure', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.failed,
                pid: 1234,
                exitCode: 2,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: const AgentActionCapturedOutput(
                  text: 'file not found',
                  isCaptured: true,
                ),
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.pid, 1234);
      expect(execution.exitCode, 2);
      expect(execution.failureCode, AgentActionFailureCode.exitCodeRejected);
      expect(execution.failurePhase, 'process_exit');
      expect(execution.failureMessage, 'Comando finalizou com codigo de saida 2.');
      expect(execution.stderrText, 'file not found');
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should deduplicate local execution by idempotency key', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'same-key',
        ),
      );
      await _waitForRunnerStarts(runner, 1);
      final second = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'same-key',
        ),
      );

      expect(runner.startedCount, 1);
      expect(repository.savedExecutions, hasLength(2));
      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      final firstResult = await first;
      final secondResult = await second;

      expect(firstResult.isSuccess(), isTrue);
      expect(secondResult.isSuccess(), isTrue);
      expect(firstResult.getOrThrow().id, secondResult.getOrThrow().id);
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should reuse persisted execution by idempotency key', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'persisted-key',
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'persisted-key',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
      expect(runner.startedCount, 0);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reuse persisted execution when idempotency key differs only by whitespace', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'persisted-key',
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: '  persisted-key  ',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
      expect(runner.startedCount, 0);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should enqueue local execution when concurrency limit is reached', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await _waitForRunnerStarts(runner, 1);
      final second = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(runner.startedCount, 1);
      expect(repository.savedExecutions.map((execution) => execution.status), [
        AgentActionExecutionStatus.queued,
        AgentActionExecutionStatus.running,
        AgentActionExecutionStatus.queued,
      ]);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
      await _waitForRunnerStarts(runner, 2);
      expect(runner.startedCount, 2);
      runner.completions[1].complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 5678,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10, 2),
            finishedAt: DateTime(2026, 5, 15, 10, 3),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      final secondResult = await second;
      expect(secondResult.isSuccess(), isTrue);
      expect(secondResult.getOrThrow().pid, 5678);
    });

    test('should reject local execution when concurrency policy rejects overlap', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            concurrencyBehavior: AgentActionConcurrencyBehavior.reject,
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await _waitForRunnerStarts(runner, 1);

      final second = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<ActionQueueFailure>());
      expect(
        (second.exceptionOrNull()! as ActionQueueFailure).code,
        AgentActionFailureCode.queueConcurrencyRejected,
      );
      expect(repository.savedExecutions.last.failureCode, AgentActionFailureCode.queueConcurrencyRejected);
      expect(repository.savedExecutions.last.failurePhase, 'queue');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
    });

    test('should persist ignored overlap as skipped with queueIgnored failure code', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            concurrencyBehavior: AgentActionConcurrencyBehavior.ignore,
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await _waitForRunnerStarts(runner, 1);

      final second = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<ActionQueueFailure>());
      expect(
        (second.exceptionOrNull()! as ActionQueueFailure).code,
        AgentActionFailureCode.queueIgnored,
      );
      expect(repository.savedExecutions.last.status, AgentActionExecutionStatus.skipped);
      expect(repository.savedExecutions.last.failureCode, AgentActionFailureCode.queueIgnored);
      expect(repository.savedExecutions.last.failurePhase, 'queue');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
    });

    test('should reject local execution when action queue is full', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 0,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await _waitForRunnerStarts(runner, 1);

      final second = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<ActionQueueFailure>());
      expect(
        repository.savedExecutions.last.failureCode,
        AgentActionFailureCode.queueFull,
      );
      expect(repository.savedExecutions.last.failurePhase, 'queue');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
    });

    test('should cancel running execution through local runner', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        processStartedAt: DateTime(2026, 5, 15, 9),
        processExecutable: 'cmd.exe',
        pid: 1234,
      );
      final runner = FakeAgentActionLocalRunner(
        result: Failure(ActionRuntimeFailure('Should not run')),
        cancelResult: const Success(
          AgentActionCancellationResult(
            executionId: 'execution-1',
            status: AgentActionExecutionStatus.killed,
            killed: true,
            pid: 1234,
            message: 'Processo principal finalizado.',
          ),
        ),
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([
          runner,
        ]),
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final result = await useCase('execution-1');

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.killed);
      expect(execution.finishedAt, DateTime(2026, 5, 15, 9, 1));
      expect(execution.failureCode, AgentActionFailureCode.executionKilled);
      expect(execution.failurePhase, 'cancel');
      expect(runner.lastExpectedPid, 1234);
      expect(runner.lastExpectedProcessExecutable, 'cmd.exe');
      expect(runner.lastExpectedProcessStartedAt, DateTime(2026, 5, 15, 9));
      expect(repository.savedExecutions.last.status, AgentActionExecutionStatus.killed);
    });

    test('should cancel running elevated execution through elevated canceller', () async {
      repository.definitions['action-elevated'] = const AgentActionDefinition(
        id: 'action-elevated',
        name: 'Elevated command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'whoami'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      repository.executions['execution-elevated'] = AgentActionExecution(
        id: 'execution-elevated',
        actionId: 'action-elevated',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 0,
      );
      final elevatedCanceller = FakeElevatedActionExecutionCanceller(
        cancelResult: const Success(
          AgentActionCancellationResult(
            executionId: 'execution-elevated',
            status: AgentActionExecutionStatus.killed,
            killed: true,
            pid: 0,
            message: 'Elevated process cancelled.',
          ),
        ),
      );
      final runner = FakeAgentActionLocalRunner(
        result: Failure(ActionRuntimeFailure('Should not run')),
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        elevatedCanceller: elevatedCanceller,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final result = await useCase('execution-elevated');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.killed);
      expect(result.getOrThrow().failureCode, AgentActionFailureCode.executionKilled);
      expect(elevatedCanceller.lastExecutionId, 'execution-elevated');
      expect(runner.cancelInvocationCount, 0);
    });

    test('should persist running cancel through SaveAgentActionExecution', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 1234,
      );
      final runner = FakeAgentActionLocalRunner(
        result: Failure(ActionRuntimeFailure('Should not run')),
        cancelResult: const Success(
          AgentActionCancellationResult(
            executionId: 'execution-1',
            status: AgentActionExecutionStatus.killed,
            killed: true,
            pid: 1234,
            message: 'Processo principal finalizado.',
          ),
        ),
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final result = await useCase('execution-1');

      expect(result.isSuccess(), isTrue);
      expect(countingSave.invocationCount, 1);
    });

    test('should reject cancel when execution already finished', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
      );

      final result = await useCase('execution-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect(
        (result.exceptionOrNull()! as ActionRuntimeFailure).context,
        containsPair('reason', AgentActionRpcConstants.agentActionCancelAlreadyFinishedErrorReason),
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should cancel queued execution before runner starts', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final queue = ActionExecutionQueue();
      final runner = ControlledAgentActionLocalRunner();
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        executionQueue: queue,
      );
      final cancelUseCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        executionQueue: queue,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final first = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await _waitForRunnerStarts(runner, 1);
      final second = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final queuedExecution = repository.savedExecutions.last;

      final cancelResult = await cancelUseCase(queuedExecution.id);

      expect(cancelResult.isSuccess(), isTrue);
      expect(cancelResult.getOrThrow().status, AgentActionExecutionStatus.cancelled);
      expect(cancelResult.getOrThrow().failureCode, AgentActionFailureCode.queueCancelled);
      expect(cancelResult.getOrThrow().failurePhase, 'queue');
      expect(runner.startedCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      expect((await first).isSuccess(), isTrue);
      final secondResult = await second;
      expect(secondResult.isError(), isTrue);
      expect(repository.executions[queuedExecution.id]?.status, AgentActionExecutionStatus.cancelled);
    });

    test('should persist queued cancel through SaveAgentActionExecution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final queue = ActionExecutionQueue();
      final runner = ControlledAgentActionLocalRunner();
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        executionQueue: queue,
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final cancelUseCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        executionQueue: queue,
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final first = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await _waitForRunnerStarts(runner, 1);
      final second = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final queuedExecution = repository.savedExecutions.last;

      final cancelResult = await cancelUseCase(queuedExecution.id);

      expect(cancelResult.isSuccess(), isTrue);
      expect(countingSave.invocationCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      expect((await first).isSuccess(), isTrue);
      await second;
    });

    test('should reject cancel when queued execution is not in memory queue', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
      );

      final result = await useCase('execution-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
      expect(
        (result.exceptionOrNull()! as ActionNotFoundFailure).context,
        containsPair('reason', AgentActionQueueConstants.queuedExecutionNotFoundReason),
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject local execution when action is not active', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.paused,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject execution when agent actions feature flag is disabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActions(false);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.featureDisabled);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote ad-hoc execution when remote ad-hoc feature flag is disabled', () async {
      repository.definitions['action-adhoc'] = AgentActionDefinition(
        id: 'action-adhoc',
        name: 'Remote ad-hoc',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            allowAdHoc: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-adhoc',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-adhoc-1',
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.remoteAdHocDisabled,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution when remote feature flag is disabled', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.remoteFeatureDisabled,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution when secret rotation invalidates risk fingerprint', () async {
      final secretStore = _InMemoryAgentActionSecretStoreForRunTests();
      await secretStore.saveSecret('api', 'version-one');
      const snapshotter = AgentActionDefinitionSnapshotter();
      final fingerprinter = AgentActionSecretReferenceFingerprinter(secretStore);
      const baseDefinition = AgentActionDefinition(
        id: 'action-1',
        name: 'Secret action',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api}'),
      );
      final approvedFingerprints = await fingerprinter.fingerprintsFor(baseDefinition);
      final approvedDefinition = baseDefinition.copyWith(
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026, 5, 15),
            approvedBy: 'local-admin',
            riskFingerprint: snapshotter.riskFingerprint(
              baseDefinition,
              secretReferenceFingerprints: approvedFingerprints,
            ),
          ),
        ),
      );
      repository.definitions['action-1'] = approvedDefinition;

      await secretStore.saveSecret('api', 'version-two');

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        definitionSnapshotter: snapshotter,
        secretReferenceFingerprinter: fingerprinter,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-1',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.remoteNotApproved);
      expect(
        failure.context['reason'],
        AgentActionGateConstants.remoteRiskFingerprintStaleReason,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution when action is not approved for remote use', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.remoteNotApproved);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution without idempotency key', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.remoteIdempotencyRequired,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject execution request with invalid runtime parameters before queueing', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {
            'invalid': Duration(seconds: 1),
          },
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidRuntimeParametersReason),
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution when runner is not configured', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.elevatedNotConfigured,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution when runner is degraded', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService()..markDegraded(reason: 'test');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.elevatedRunnerDegraded,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution for unsupported action type', () async {
      final tempDir = await Directory.systemTemp.createTemp('elevated_type_gate_');
      addTearDown(() => tempDir.delete(recursive: true));
      final storage = GlobalStorageContext(appDirectoryPath: tempDir.path);
      final marker = File(AgentActionElevatedConstants.readyMarkerPath(tempDir.path));
      await marker.parent.create(recursive: true);
      await marker.writeAsString('ok');

      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Send mail',
        state: AgentActionState.active,
        config: EmailActionConfig(
          smtpProfileId: 'smtp-1',
          from: 'agent@example.com',
          to: ['ops@example.com'],
          subjectTemplate: 'subject',
          bodyTemplate: 'body',
        ),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService()..refresh(storage);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
        elevatedExecutionService: ElevatedAgentActionExecutionService(
          bridge: _NoOpElevatedBridge(),
          statusFileSyncer: ElevatedActionStatusFileSyncer(storageContext: storage),
          readiness: readiness,
        ),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.unsupportedForElevatedRunner,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution when elevated feature flag is disabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(false);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.elevatedDisabled);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject scheduled execution when maintenance mode is enabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.scheduler,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.maintenanceMode);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should allow local execution when maintenance mode is enabled without strict mode', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final runtimeStateGuard = AgentActionRuntimeStateGuard(flags)..markMaintenance(reason: 'operator');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        runtimeStateGuard: runtimeStateGuard,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(repository.savedExecutions, isNotEmpty);
    });

    test('should reject local execution when maintenance strict mode is enabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      await flags.setEnableAgentActionsMaintenanceStrictMode(true);
      final runtimeStateGuard = AgentActionRuntimeStateGuard(flags)..markMaintenance(reason: 'operator');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        runtimeStateGuard: runtimeStateGuard,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.maintenanceMode);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution while subsystem is draining', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runtimeStateGuard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        runtimeStateGuard: runtimeStateGuard,
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-key-1',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.subsystemDraining);
      expect(failure.context['reason'], AgentActionRuntimeStateConstants.agentActionsDrainingReason);
      expect(repository.savedExecutions, isEmpty);
    });
  });
}

class _MemoryRemoteAuditStore implements IAgentActionRemoteAuditStore {
  final List<AgentActionRemoteAuditRecord> rows = <AgentActionRemoteAuditRecord>[];

  @override
  Future<void> append(AgentActionRemoteAuditRecord record) async {
    rows.add(record);
  }

  @override
  Future<List<AgentActionRemoteAuditRecord>> listRecent({int limit = 200}) async =>
      List<AgentActionRemoteAuditRecord>.from(rows);

  @override
  Future<int> deleteWhereOccurredBefore({
    required DateTime cutoffUtc,
    required int limit,
  }) async => 0;
}

Future<void> _waitForRunnerStarts(
  ControlledAgentActionLocalRunner runner,
  int expectedCount,
) async {
  while (runner.startedCount < expectedCount) {
    await Future<void>.delayed(Duration.zero);
  }
  await runner.starts[expectedCount - 1].future;
}

class _NoOpElevatedBridge implements IElevatedActionRunnerBridge {
  @override
  Future<Result<void>> submitExecution({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    return const Success(unit);
  }
}

class _InMemoryAgentActionSecretStoreForRunTests implements IAgentActionSecretStore {
  final Map<String, String> _secrets = <String, String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    _secrets.remove(secretName);
  }

  @override
  Future<bool> exists(String secretName) async => _secrets.containsKey(secretName);

  @override
  Future<String?> readSecret(String secretName) async => _secrets[secretName];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    _secrets[secretName] = secretValue;
  }
}
