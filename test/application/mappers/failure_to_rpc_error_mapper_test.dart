import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_queue_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

void main() {
  group('FailureToRpcErrorMapper', () {
    test('preserves execution_preflight phase and domain path snapshot reason for path validation failures', () {
      final failure = ActionValidationFailure.withContext(
        message: 'Working directory mudou desde a ultima validacao.',
        code: AgentActionFailureCode.pathSnapshotMismatch,
        context: const {
          'phase': 'execution_preflight',
          'reason': AgentActionPathContextConstants.pathChangedAfterSaveReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.invalidParams);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['phase'], 'execution_preflight');
      expect(data['reason'], AgentActionPathContextConstants.pathChangedAfterSaveReason);
      expect(data.containsKey('odbc_reason'), isFalse);
    });

    test('preserves queue phase and remote rate limit diagnostic for queue full failures', () {
      final failure = ActionQueueFailure.withContext(
        message: 'Fila cheia.',
        code: AgentActionFailureCode.queueFull,
        context: const {
          'phase': 'queue',
          'reason': AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.rateLimited);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['phase'], 'queue');
      expect(data['reason'], RpcErrorCode.getReason(RpcErrorCode.rateLimited));
      expect(data['odbc_reason'], AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason);
    });

    test('preserves queue concurrency diagnostic for concurrency rejected queue failures', () {
      final failure = ActionQueueFailure.withContext(
        message: 'Action execution was rejected because the concurrency limit was reached.',
        code: AgentActionFailureCode.queueConcurrencyRejected,
        context: const {
          'phase': 'queue',
          'reason': AgentActionQueueConstants.concurrencyLimitReachedReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.invalidParams);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['corrective_action'], isNull);
      expect(data['failure_code'], AgentActionFailureCode.queueConcurrencyRejected);
      expect(data['reason'], RpcErrorCode.getReason(RpcErrorCode.invalidParams));
      expect(data['odbc_reason'], AgentActionQueueConstants.concurrencyLimitReachedReason);
    });

    test('preserves kill failed diagnostic for kill failed action runtime failures', () {
      final failure = ActionRuntimeFailure.withContext(
        message: 'Kill failed.',
        code: AgentActionFailureCode.killFailed,
        context: const {
          'reason': AgentActionRpcConstants.agentActionCancelKillFailedErrorReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.internalError);
      expect(data['corrective_action'], isNull);
      expect(data['failure_code'], AgentActionFailureCode.killFailed);
      expect(data['odbc_reason'], AgentActionRpcConstants.agentActionCancelKillFailedErrorReason);
    });

    test('preserves kill permission denied diagnostic for permission failures', () {
      final failure = ActionRuntimeFailure.withContext(
        message: 'Kill permission denied.',
        code: AgentActionFailureCode.killPermissionDenied,
        context: const {
          'reason': AgentActionProcessConstants.killPermissionDeniedReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.internalError);
      expect(data['failure_code'], AgentActionFailureCode.killPermissionDenied);
      expect(data['odbc_reason'], AgentActionProcessConstants.killPermissionDeniedReason);
    });

    test('maps elevated runner not configured to agentActionsTemporarilyUnavailable RPC code', () {
      final failure = ActionAuthorizationFailure.withContext(
        message: 'Elevated agent action runner is not configured on this host.',
        code: AgentActionFailureCode.elevatedNotConfigured,
        context: const {
          'reason': AgentActionGateConstants.elevatedNotConfiguredReason,
          'user_message': 'Prepare o runner elevado.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.agentActionsTemporarilyUnavailable);
      expect(data['reason'], AgentActionGateConstants.elevatedNotConfiguredReason);
      expect(data['user_message'], 'Prepare o runner elevado.');
    });

    test('maps elevated submit failure to agentActionsTemporarilyUnavailable RPC code', () {
      final failure = ActionRuntimeFailure.withContext(
        message: 'Failed to submit elevated execution.',
        code: AgentActionFailureCode.elevatedSubmitFailed,
        context: const {
          'reason': AgentActionGateConstants.elevatedSubmitFailedReason,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.agentActionsTemporarilyUnavailable);
      expect(data['reason'], AgentActionGateConstants.elevatedSubmitFailedReason);
    });

    test('maps draining subsystem failure to agentActionsTemporarilyUnavailable RPC code', () {
      final failure = ActionAuthorizationFailure.withContext(
        message: 'Agent actions subsystem is not ready to accept this execution.',
        code: AgentActionFailureCode.subsystemDraining,
        context: {
          'rpc_error_code': RpcErrorCode.agentActionsTemporarilyUnavailable,
          'reason': AgentActionRuntimeStateConstants.agentActionsDrainingReason,
          'user_message': 'O agente esta drenando.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.agentActionsTemporarilyUnavailable);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['retryable'], isTrue);
      expect(data['reason'], AgentActionRuntimeStateConstants.agentActionsDrainingReason);
      expect(data.containsKey('odbc_reason'), isFalse);
      expect(data['user_message'], 'O agente esta drenando.');
    });

    test('preserves user_message and remote approval app-close conflict diagnostic', () {
      final failure = ActionValidationFailure.withContext(
        message: 'Action cannot be approved for remote execution while an app-close trigger exists for this action.',
        code: AgentActionFailureCode.remoteApprovalAppCloseConflict,
        context: const {
          'reason': AgentActionTriggerConstants.remoteApprovalAppCloseConflictReason,
          'user_message':
              'Remova ou exclua o gatilho de encerramento desta acao antes de aprovar a execucao remota pelo hub.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.invalidParams);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['corrective_action'], isNull);
      expect(data['reason'], AgentActionTriggerConstants.remoteApprovalAppCloseConflictReason);
      expect(data['user_message'], contains('Remova'));
      expect(data.containsKey('odbc_reason'), isFalse);
    });

    test('preserves user_message and app-close blocked diagnostic for elevated action', () {
      final failure = ActionValidationFailure.withContext(
        message: 'App-close trigger cannot be saved because the action requires elevated execution.',
        code: AgentActionFailureCode.appCloseElevatedActionBlocked,
        context: const {
          'reason': AgentActionTriggerConstants.appCloseElevatedActionBlockedReason,
          'user_message':
              'Nao e possivel salvar um gatilho de encerramento para uma acao que exige execucao elevada (UAC).',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.invalidParams);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['reason'], AgentActionTriggerConstants.appCloseElevatedActionBlockedReason);
      expect(data['user_message'], contains('elevada'));
    });

    test('preserves user_message and app-close blocked diagnostic for remote-approved action', () {
      final failure = ActionValidationFailure.withContext(
        message: 'App-close trigger cannot be saved because the action is approved for remote execution.',
        code: AgentActionFailureCode.appCloseRemoteActionBlocked,
        context: const {
          'reason': AgentActionTriggerConstants.appCloseRemoteActionBlockedReason,
          'user_message':
              'Nao e possivel salvar um gatilho de encerramento para uma acao aprovada para execucao remota pelo hub.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.invalidParams);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['corrective_action'], isNull);
      expect(data['reason'], AgentActionTriggerConstants.appCloseRemoteActionBlockedReason);
      expect(data['user_message'], contains('Nao e possivel'));
      expect(data.containsKey('odbc_reason'), isFalse);
    });

    test('maps remote not approved to unauthorized with stable action reason', () {
      final failure = ActionAuthorizationFailure.withContext(
        message: 'Action is not approved for remote execution.',
        code: AgentActionFailureCode.remoteNotApproved,
        context: const {
          'reason': AgentActionGateConstants.remoteActionNotApprovedReason,
          'user_message': 'A acao nao esta aprovada para execucao remota.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.unauthorized);
      expect(data['reason'], AgentActionGateConstants.remoteActionNotApprovedReason);
      expect(data['category'], RpcErrorCode.categoryAction);
    });

    test('maps stale remote risk fingerprint to unauthorized with dedicated reason', () {
      final failure = ActionAuthorizationFailure.withContext(
        message: 'Remote action approval is stale after a risk-bearing change.',
        code: AgentActionFailureCode.remoteNotApproved,
        context: const {
          'reason': AgentActionGateConstants.remoteRiskFingerprintStaleReason,
          'remote_requires_reapproval': true,
          'user_message':
              'A aprovacao remota desta acao nao reflete mais a configuracao atual (por exemplo, segredo rotacionado). Reaprove na pagina Acoes antes de executar pelo Hub.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.unauthorized);
      expect(data['reason'], AgentActionGateConstants.remoteRiskFingerprintStaleReason);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['failure_code'], AgentActionFailureCode.remoteNotApproved);
    });

    test('maps environment profile denied to unauthorized with stable action reason', () {
      final failure = ActionAuthorizationFailure.withContext(
        message: 'Action is not allowed in the current agent operational profile.',
        code: AgentActionFailureCode.environmentProfileDenied,
        context: const {
          'reason': AgentActionGateConstants.environmentProfileDeniedReason,
          'user_message': 'Perfil operacional nao autorizado.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.unauthorized);
      expect(data['reason'], AgentActionGateConstants.environmentProfileDeniedReason);
    });

    test('maps secret unavailable to invalidParams with stable action reason', () {
      final failure = ActionValidationFailure.withContext(
        message: 'Referenced action secrets are not available.',
        code: AgentActionFailureCode.secretUnavailable,
        context: const {
          'reason': AgentActionGateConstants.secretUnavailableReason,
          'user_message': 'Configure os segredos.',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, RpcErrorCode.invalidParams);
      expect(data['reason'], AgentActionGateConstants.secretUnavailableReason);
    });
  });
}
