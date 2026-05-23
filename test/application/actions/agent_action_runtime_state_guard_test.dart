import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

void main() {
  group('AgentActionRuntimeStateGuard', () {
    test('allows execution while ready', () {
      final guard = AgentActionRuntimeStateGuard();

      final result = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('blocks remote execution while starting and maps rpc_error_code', () {
      final guard = AgentActionRuntimeStateGuard()..markStarting(reason: 'boot');

      final result = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.subsystemStarting);
      expect(failure.context['rpc_error_code'], RpcErrorCode.agentActionsTemporarilyUnavailable);
    });

    test('blocks remote execution while draining', () {
      final guard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');

      final result = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.subsystemDraining);
      expect(failure.context['reason'], AgentActionRuntimeStateConstants.agentActionsDrainingReason);
      expect(failure.context['detail'], 'shutdown');
      expect(failure.context['rpc_error_code'], RpcErrorCode.agentActionsTemporarilyUnavailable);
    });

    test('allows app close lifecycle execution while draining', () {
      final guard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');

      final result = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.appLifecycle,
          triggerType: AgentActionTriggerType.appClose,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('blocks app close trigger type when source is not app lifecycle during draining', () {
      final guard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');

      final result = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          triggerType: AgentActionTriggerType.appClose,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(result.isError(), isTrue);
    });

    test('allows local UI execution while maintenance blocks non-manual sources', () {
      final guard = AgentActionRuntimeStateGuard()..markMaintenance(reason: 'operator');

      final localResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
        actionType: AgentActionType.commandLine,
      );
      final remoteResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(localResult.isSuccess(), isTrue);
      expect(remoteResult.isError(), isTrue);
      final failure = remoteResult.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.maintenanceMode);
    });

    test('blocks local UI execution when maintenance strict mode is enabled', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceStrictMode(true);
      final guard = AgentActionRuntimeStateGuard(flags)..markMaintenance(reason: 'operator');

      final localResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
        actionType: AgentActionType.commandLine,
      );

      expect(localResult.isError(), isTrue);
      final failure = localResult.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.maintenanceMode);
      expect(
        failure.context['user_message'],
        'Todas as execucoes estao bloqueadas pelo modo de manutencao, incluindo execucao manual.',
      );
    });

    test('blocks only unavailable action types while degraded', () {
      final guard = AgentActionRuntimeStateGuard()
        ..markDegraded(
          unavailableActionTypes: {AgentActionType.commandLine},
          reason: 'runner_unavailable',
        );

      final commandLineResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.commandLine,
      );
      final emailResult = guard.ensureCanAcceptExecution(
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
        actionType: AgentActionType.email,
      );

      expect(commandLineResult.isError(), isTrue);
      expect(emailResult.isSuccess(), isTrue);
      final failure = commandLineResult.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.subsystemDegraded);
      expect(failure.context['reason'], AgentActionRuntimeStateConstants.agentActionsDegradedReason);
    });
  });
}
