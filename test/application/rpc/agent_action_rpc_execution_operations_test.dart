import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_audit_operations.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_execution_operations.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_support.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_remote_infrastructure.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockRunAgentActionViaRemoteTrigger extends Mock implements RunAgentActionViaRemoteTrigger {}

class MockRunAgentActionLocally extends Mock implements RunAgentActionLocally {}

RpcResponse _invalidParams(
  RpcRequest request,
  String detail, {
  String? rpcReason,
  Map<String, dynamic> extraFields = const <String, dynamic>{},
}) {
  const code = RpcErrorCode.invalidParams;
  return RpcResponse.error(
    id: request.id,
    error: RpcError(
      code: code,
      message: RpcErrorCode.getMessage(code),
      data: RpcErrorCode.buildErrorData(
        code: code,
        technicalMessage: detail,
        correlationId: request.id?.toString(),
        reason: rpcReason ?? RpcErrorCode.getReason(code),
        extra: <String, dynamic>{
          'detail': detail,
          'method': request.method,
          ...extraFields,
        },
      ),
    ),
  );
}

RpcResponse _internalError(RpcRequest request, String detail) {
  const code = RpcErrorCode.internalError;
  return RpcResponse.error(
    id: request.id,
    error: RpcError(
      code: code,
      message: RpcErrorCode.getMessage(code),
      data: RpcErrorCode.buildErrorData(
        code: code,
        technicalMessage: detail,
        correlationId: request.id?.toString(),
        extra: <String, dynamic>{'detail': detail},
      ),
    ),
  );
}

AgentActionRpcExecutionOperations _buildOperations({
  required FeatureFlags featureFlags,
  RunAgentActionViaRemoteTrigger? remoteRunner,
  RunAgentActionLocally? localRunner,
}) {
  final support = AgentActionRpcMethodHandlerSupport(
    invalidParams: _invalidParams,
    internalError: _internalError,
    consumeIdempotentCacheIfAny: (_, _, _) async => null,
    storeIdempotentSuccessIfApplicable:
        ({required request, required idempotencyKey, required idempotencyFingerprint, required response}) async {},
    runIdempotentExecution:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required execute,
          idempotentCachePrefetched = false,
        }) async => execute(),
  );
  final infrastructure = AgentActionRpcRemoteInfrastructure(
    featureFlags: featureFlags,
    support: support,
  );
  final audit = AgentActionRpcAuditOperations(
    uuid: const Uuid(),
    featureFlags: featureFlags,
    infrastructure: infrastructure,
  );
  return AgentActionRpcExecutionOperations(
    infrastructure: infrastructure,
    audit: audit,
    runAgentActionLocally: localRunner,
    runAgentActionViaRemoteTrigger: remoteRunner,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-1',
      ),
    );
  });

  group('AgentActionRpcExecutionOperations', () {
    late MockFeatureFlags featureFlags;

    setUp(() {
      featureFlags = MockFeatureFlags();
      when(() => featureFlags.enableAgentActions).thenReturn(true);
      when(() => featureFlags.enableRemoteAgentActions).thenReturn(true);
      when(() => featureFlags.enableAgentActionsMaintenanceMode).thenReturn(false);
      when(() => featureFlags.enableSocketIdempotency).thenReturn(false);
      when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(false);
    });

    test('handleAgentActionRun returns internal error when remote runner is not configured', () async {
      final operations = _buildOperations(featureFlags: featureFlags);

      final response = await operations.handleAgentActionRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 1,
          params: <String, dynamic>{'action_id': 'action-1'},
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error?.code, RpcErrorCode.internalError);
      expect(
        (response.error?.data as Map<String, dynamic>?)?['detail'],
        contains('Remote agent action trigger dispatch is not configured'),
      );
    });

    test('handleAgentActionRun rejects missing action_id', () async {
      final remoteRunner = MockRunAgentActionViaRemoteTrigger();
      final operations = _buildOperations(
        featureFlags: featureFlags,
        remoteRunner: remoteRunner,
      );

      final response = await operations.handleAgentActionRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 2,
          params: <String, dynamic>{},
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error?.code, RpcErrorCode.invalidParams);
      verifyNever(
        () => remoteRunner(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('handleAgentActionRun returns sanitized execution on success', () async {
      final remoteRunner = MockRunAgentActionViaRemoteTrigger();
      final execution = AgentActionExecution(
        id: 'exec-ops-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 6, 11),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-ops',
        requestedBy: 'hub',
        traceId: 'trace-ops',
        redactionApplied: true,
      );
      when(
        () => remoteRunner(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      final operations = _buildOperations(
        featureFlags: featureFlags,
        remoteRunner: remoteRunner,
      );

      final response = await operations.handleAgentActionRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 3,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-ops',
          },
          meta: RpcProtocolMeta(traceId: 'trace-ops', requestId: 'hub-req'),
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isTrue);
      final result = response.result! as Map<String, dynamic>;
      expect(result['execution_id'], 'exec-ops-1');
      expect(result.containsKey('stdout_text'), isFalse);
    });

    test('handleAgentActionValidateRun rejects when no enabled remote trigger exists', () async {
      final remoteRunner = MockRunAgentActionViaRemoteTrigger();
      final localRunner = MockRunAgentActionLocally();
      when(
        () => remoteRunner.resolveEnabledRemoteTriggerId(
          actionId: any(named: 'actionId'),
          triggerId: any(named: 'triggerId'),
        ),
      ).thenAnswer(
        (_) async => Failure(
          ActionValidationFailure.withContext(
            message: 'Remote agent action run requires an enabled remote trigger.',
            code: AgentActionFailureCode.remoteTriggerRequired,
            context: const {
              'reason': AgentActionTriggerConstants.remoteTriggerRequiredReason,
            },
          ),
        ),
      );

      final operations = _buildOperations(
        featureFlags: featureFlags,
        remoteRunner: remoteRunner,
        localRunner: localRunner,
      );

      final response = await operations.handleAgentActionValidateRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          id: 4,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-ops',
          },
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error?.code, RpcErrorCode.invalidParams);
      expect(
        (response.error?.data as Map<String, dynamic>?)?['reason'],
        AgentActionTriggerConstants.remoteTriggerRequiredReason,
      );
      verifyNever(() => localRunner.validateRemoteRun(any()));
    });

    test('handleAgentActionValidateRun calls validateRemoteRun after remote trigger admission', () async {
      final remoteRunner = MockRunAgentActionViaRemoteTrigger();
      final localRunner = MockRunAgentActionLocally();
      when(
        () => remoteRunner.resolveEnabledRemoteTriggerId(
          actionId: any(named: 'actionId'),
          triggerId: any(named: 'triggerId'),
        ),
      ).thenAnswer((_) async => const Success('remote-1'));
      when(() => localRunner.validateRemoteRun(any())).thenAnswer(
        (_) async => const Success(
          AgentActionValidateRunSummary(
            actionId: 'action-1',
            actionType: AgentActionType.commandLine,
          ),
        ),
      );

      final operations = _buildOperations(
        featureFlags: featureFlags,
        remoteRunner: remoteRunner,
        localRunner: localRunner,
      );

      final response = await operations.handleAgentActionValidateRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          id: 5,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-ops',
          },
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isTrue);
      final result = response.result! as Map<String, dynamic>;
      expect(result['valid'], isTrue);
      expect(result['action_id'], 'action-1');
      verify(() => localRunner.validateRemoteRun(any())).called(1);
    });
  });
}
