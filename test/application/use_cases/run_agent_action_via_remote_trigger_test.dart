import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/agent_action_use_case_test_support.dart'
    show FakeAgentActionLocalRunner, FakeAgentActionRepository;

const _structuredTestConfig = ExecutableActionConfig(
  executablePath: AgentActionPathReference(originalPath: r'C:\\tools\\test.exe'),
);

void main() {
  group('RunAgentActionViaRemoteTrigger', () {
    test('should dispatch the sole enabled remote trigger for the action', () async {
      final repository = FakeAgentActionRepository();
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Remote action',
        state: AgentActionState.active,
        config: _structuredTestConfig,
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026, 5, 19),
            approvedBy: 'local-admin',
          ),
        ),
      );
      repository.triggers['remote-1'] = const AgentActionTrigger(
        id: 'remote-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActions(true);
      await flags.setEnableRemoteAgentActions(true);
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            actionType: AgentActionType.executable,
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1,
                exitCode: 0,
                processStartedAt: DateTime.utc(2026, 5, 19),
                finishedAt: DateTime.utc(2026, 5, 19, 0, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime.utc(2026, 5, 19),
      );
      final useCase = RunAgentActionViaRemoteTrigger(
        repository,
        DispatchAgentActionTrigger(repository, runUseCase),
      );

      final result = await useCase(
        actionId: 'action-1',
        idempotencyKey: 'hub-idem-1',
        traceId: 'trace-1',
        requestedBy: 'hub',
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.triggerId, 'remote-1');
      expect(execution.triggerType, AgentActionTriggerType.remote);
      expect(execution.source, AgentActionRequestSource.remoteHub);
    });

    test('should reject when no enabled remote trigger exists', () async {
      final repository = FakeAgentActionRepository();
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Remote action',
        state: AgentActionState.active,
        config: _structuredTestConfig,
      );
      final useCase = RunAgentActionViaRemoteTrigger(
        repository,
        DispatchAgentActionTrigger(
          repository,
          RunAgentActionLocally(
            repository,
            AgentActionLocalRunnerRegistry([
              FakeAgentActionLocalRunner(
                actionType: AgentActionType.executable,
                result: Failure(ActionRuntimeFailure('should not run')),
              ),
            ]),
            const Uuid(),
          ),
        ),
      );

      final result = await useCase(
        actionId: 'action-1',
        idempotencyKey: 'hub-idem-1',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteTriggerRequired);
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.remoteTriggerRequiredReason,
      );
    });

    test('should resolve the enabled remote trigger without dispatching', () async {
      final repository = FakeAgentActionRepository();
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Remote action',
        state: AgentActionState.active,
        config: _structuredTestConfig,
      );
      repository.triggers['remote-1'] = const AgentActionTrigger(
        id: 'remote-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );
      final useCase = RunAgentActionViaRemoteTrigger(
        repository,
        DispatchAgentActionTrigger(
          repository,
          RunAgentActionLocally(
            repository,
            AgentActionLocalRunnerRegistry([
              FakeAgentActionLocalRunner(
                actionType: AgentActionType.executable,
                result: Failure(ActionRuntimeFailure('should not run')),
              ),
            ]),
            const Uuid(),
          ),
        ),
      );

      final result = await useCase.resolveEnabledRemoteTriggerId(actionId: 'action-1');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 'remote-1');
      expect(repository.savedExecutions, isEmpty);
    });

    test('should report a missing action instead of requiring a remote trigger', () async {
      final useCase = _useCase(FakeAgentActionRepository());

      final result = await useCase.resolveEnabledRemoteTriggerId(actionId: 'missing-action');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionNotFoundFailure;
      expect(failure.context['action_id'], 'missing-action');
      expect(failure.context['reason'], AgentActionRpcConstants.agentActionExecutionNotFoundContextReason);
      expect(failure.context['user_message'], 'A acao informada nao foi encontrada.');
    });

    test('should name the owning action when the requested action does not exist', () async {
      final repository = FakeAgentActionRepository();
      repository.definitions['action-owner'] = const AgentActionDefinition(
        id: 'action-owner',
        name: 'Owner',
        state: AgentActionState.active,
        config: _structuredTestConfig,
      );
      repository.triggers['remote-1'] = const AgentActionTrigger(
        id: 'remote-1',
        actionId: 'action-owner',
        type: AgentActionTriggerType.remote,
      );
      final useCase = _useCase(repository);

      final result = await useCase.resolveEnabledRemoteTriggerId(
        actionId: 'missing-action',
        triggerId: 'remote-1',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionNotFoundFailure;
      expect(failure.context['trigger_action_id'], 'action-owner');
      expect(
        failure.context['user_message'],
        'A acao informada nao foi encontrada. O gatilho informado pertence a acao action-owner.',
      );
    });

    test('should name the owning action when the remote trigger belongs to another action', () async {
      final repository = FakeAgentActionRepository();
      repository.definitions['action-requested'] = const AgentActionDefinition(
        id: 'action-requested',
        name: 'Requested',
        state: AgentActionState.active,
        config: _structuredTestConfig,
      );
      repository.definitions['action-owner'] = const AgentActionDefinition(
        id: 'action-owner',
        name: 'Owner',
        state: AgentActionState.active,
        config: _structuredTestConfig,
      );
      repository.triggers['remote-1'] = const AgentActionTrigger(
        id: 'remote-1',
        actionId: 'action-owner',
        type: AgentActionTriggerType.remote,
      );
      final useCase = _useCase(repository);

      final result = await useCase.resolveEnabledRemoteTriggerId(
        actionId: 'action-requested',
        triggerId: 'remote-1',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteTriggerInvalid);
      expect(failure.context['trigger_action_id'], 'action-owner');
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.remoteTriggerActionMismatchReason,
      );
      expect(
        failure.context['user_message'],
        'O gatilho remoto informado nao pertence a esta acao. Ele pertence a acao action-owner.',
      );
    });
  });
}

RunAgentActionViaRemoteTrigger _useCase(FakeAgentActionRepository repository) {
  return RunAgentActionViaRemoteTrigger(
    repository,
    DispatchAgentActionTrigger(
      repository,
      RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            actionType: AgentActionType.executable,
            result: Failure(ActionRuntimeFailure('should not run')),
          ),
        ]),
        const Uuid(),
      ),
    ),
  );
}
