import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _CoordinatorFakeRepository implements IAgentActionRepository {
  final Map<String, AgentActionDefinition> definitions = <String, AgentActionDefinition>{};
  final Map<String, AgentActionTrigger> triggers = <String, AgentActionTrigger>{};
  final Map<String, AgentActionExecution> executions = <String, AgentActionExecution>{};

  @override
  Future<Result<AgentActionDefinition>> saveDefinition(AgentActionDefinition definition) async => Success(definition);

  @override
  Future<Result<AgentActionDefinition>> getDefinition(String id) async => Failure(ActionNotFoundFailure('missing'));

  @override
  Future<Result<List<AgentActionDefinition>>> listDefinitions() async => const Success(<AgentActionDefinition>[]);

  @override
  Future<Result<void>> deleteDefinition(String id) async => const Success(unit);

  @override
  Future<Result<AgentActionTrigger>> saveTrigger(AgentActionTrigger trigger) async => Success(trigger);

  @override
  Future<Result<AgentActionTrigger>> getTrigger(String id) async => Failure(ActionNotFoundFailure('missing'));

  @override
  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async => const Success(<AgentActionTrigger>[]);

  @override
  Future<Result<void>> deleteTrigger(String id) async => const Success(unit);

  @override
  Future<Result<AgentActionExecution>> saveExecution(AgentActionExecution execution) async => Success(execution);

  @override
  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async => Failure(ActionNotFoundFailure('missing'));

  @override
  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) async => Success(
    (
      text: '',
      nextOffset: offsetUtf8,
      totalBytes: 0,
      responseTruncated: false,
      effectiveStart: offsetUtf8,
    ),
  );

  @override
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async => const Success(<AgentActionExecution>[]);

  @override
  Future<Result<int>> cleanupExecutions({required DateTime olderThan}) async => const Success(0);

  @override
  Future<Result<int>> clearCapturedOutputOlderThan({required DateTime olderThan}) async => const Success(0);
}

void main() {
  group('AgentActionSubsystemCoordinator', () {
    late FeatureFlags featureFlags;
    late AgentActionRuntimeStateGuard guard;
    late AgentActionTriggerScheduler scheduler;
    late AgentActionSubsystemCoordinator coordinator;

    setUp(() {
      featureFlags = FeatureFlags(InMemoryAppSettingsStore());
      guard = AgentActionRuntimeStateGuard();
      scheduler = AgentActionTriggerScheduler(
        _CoordinatorFakeRepository(),
        DispatchAgentActionTrigger(
          _CoordinatorFakeRepository(),
          RunAgentActionLocally(
            _CoordinatorFakeRepository(),
            AgentActionLocalRunnerRegistry(const []),
            const Uuid(),
            featureFlags: featureFlags,
          ),
        ),
        featureFlags: featureFlags,
      );
      coordinator = AgentActionSubsystemCoordinator(guard, scheduler, featureFlags);
    });

    test('should enter maintenance mode after draining and stopping scheduler', () async {
      await coordinator.enterMaintenanceMode();

      expect(featureFlags.enableAgentActionsMaintenanceMode, isTrue);
      expect(guard.snapshot.status, AgentActionSubsystemStatus.maintenance);
      expect(scheduler.scheduledTimerCount, 0);

      final remoteResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );
      expect(remoteResult.isError(), isTrue);

      final localResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
        actionType: AgentActionType.commandLine,
      );
      expect(localResult.isSuccess(), isTrue);
    });

    test('should exit maintenance mode and restore ready state', () async {
      await coordinator.enterMaintenanceMode();

      await coordinator.exitMaintenanceMode();

      expect(featureFlags.enableAgentActionsMaintenanceMode, isFalse);
      expect(guard.snapshot.status, AgentActionSubsystemStatus.ready);
    });

    test('should disable remote actions after draining without disabling local feature', () async {
      await featureFlags.setEnableRemoteAgentActions(true);

      await coordinator.disableRemoteAgentActions();

      expect(featureFlags.enableRemoteAgentActions, isFalse);
      expect(featureFlags.enableAgentActions, isTrue);
      expect(guard.snapshot.status, AgentActionSubsystemStatus.ready);
    });

    test('should block remote execution while draining for protocol rollback', () async {
      await featureFlags.setEnableRemoteAgentActions(true);
      guard.markDraining(reason: AgentActionRuntimeStateConstants.remoteProtocolRollbackReason);

      final remoteResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(remoteResult.isError(), isTrue);
      expect(
        (remoteResult.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.subsystemDraining,
      );
    });
  });
}
