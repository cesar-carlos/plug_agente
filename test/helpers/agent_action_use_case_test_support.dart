import 'dart:async';

import 'package:plug_agente/application/actions/agent_action_dangerous_command_policy_enforcer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
import 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

export 'dart:async';
export 'dart:io';
export 'package:flutter_test/flutter_test.dart';
export 'package:plug_agente/application/actions/action_execution_queue.dart';
export 'package:plug_agente/application/actions/agent_action_dangerous_command_policy_enforcer.dart';
export 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
export 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
export 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
export 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
export 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
export 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
export 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
export 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
export 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
export 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
export 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
export 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
export 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
export 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
export 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
export 'package:plug_agente/application/use_cases/get_agent_action_trigger.dart';
export 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
export 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
export 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
export 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
export 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
export 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
export 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
export 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
export 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
export 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
export 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
export 'package:plug_agente/core/config/feature_flags.dart';
export 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
export 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
export 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
export 'package:plug_agente/core/constants/agent_action_queue_constants.dart';
export 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
export 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
export 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
export 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
export 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
export 'package:plug_agente/core/settings/app_settings_store.dart';
export 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
export 'package:plug_agente/domain/actions/actions.dart';
export 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
export 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
export 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
export 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
export 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
export 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
export 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';
export 'package:result_dart/result_dart.dart';
export 'package:uuid/uuid.dart';

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
      lastPreflightValidatedAt: DateTime.now().toUtc(),
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

  @override
  Future<void> cancelAllPendingExecutions() async {}
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

RunAgentActionLocally runUseCaseWithDangerousCommandPolicy({
  required FakeAgentActionRepository repository,
  required FeatureFlags featureFlags,
  required Result<AgentActionProcessResult> runnerResult,
  List<AgentActionLocalRunner>? runners,
  DateTime Function()? now,
}) {
  final dangerousCommandPolicyEnforcer = AgentActionDangerousCommandPolicyEnforcer(
    commandSafetyAssessor: const ActionCommandSafetyValidator(),
    featureFlags: featureFlags,
  );
  return RunAgentActionLocally(
    repository,
    AgentActionLocalRunnerRegistry(
      runners ??
          <AgentActionLocalRunner>[
            FakeAgentActionLocalRunner(result: runnerResult),
          ],
    ),
    const Uuid(),
    featureFlags: featureFlags,
    dangerousCommandPolicyEnforcer: dangerousCommandPolicyEnforcer,
    now: now,
  );
}

class MemoryRemoteAuditStore implements IAgentActionRemoteAuditStore {
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

Future<void> waitForRunnerStarts(
  ControlledAgentActionLocalRunner runner,
  int expectedCount,
) async {
  while (runner.startedCount < expectedCount) {
    await Future<void>.delayed(Duration.zero);
  }
  await runner.starts[expectedCount - 1].future;
}

class NoOpElevatedBridge implements IElevatedActionRunnerBridge {
  @override
  Future<Result<void>> submitExecution({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    return const Success(unit);
  }
}

class InMemoryAgentActionSecretStoreForRunTests implements IAgentActionSecretStore {
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

late FakeAgentActionRepository agentActionUseCaseTestRepository;
late ValidateAgentActionDefinition agentActionUseCaseValidateDefinition;
late FeatureFlags agentActionUseCaseFeatureFlags;

void setUpAgentActionUseCaseTests() {
  agentActionUseCaseTestRepository = FakeAgentActionRepository();
  agentActionUseCaseFeatureFlags = FeatureFlags(InMemoryAppSettingsStore());
  agentActionUseCaseValidateDefinition = ValidateAgentActionDefinition(
    AgentActionAdapterRegistry([
      const FakeCommandLineActionAdapter(),
    ]),
  );
}
