import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:plug_agente/infrastructure/metrics/rpc_dispatch_metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockRunAgentActionLocally extends Mock implements RunAgentActionLocally {}

class MockRunAgentActionViaRemoteTrigger extends Mock implements RunAgentActionViaRemoteTrigger {}

class MockCancelAgentActionExecution extends Mock implements CancelAgentActionExecution {}

class MockGetAgentActionExecution extends Mock implements GetAgentActionExecution {}

class MockSliceAgentActionCapturedOutput extends Mock implements SliceAgentActionCapturedOutput {}

class MockGetAgentActionDefinition extends Mock implements GetAgentActionDefinition {}

class MockIdempotencyStore extends Mock implements IIdempotencyStore {}

class MockAgentActionRemoteAuditStore extends Mock implements IAgentActionRemoteAuditStore {}

HealthService _healthService(IDatabaseGateway gateway) => HealthService(
  metricsCollector: MetricsCollector(),
  gateway: gateway,
);

AgentActionRemoteAuthorizationService _agentActionRemoteAuthorization({
  required FeatureFlags featureFlags,
  required GetClientTokenPolicy getClientTokenPolicy,
  required AuthorizeSqlOperation authorizeSqlOperation,
}) {
  return AgentActionRemoteAuthorizationService(
    featureFlags: featureFlags,
    getClientTokenPolicy: getClientTokenPolicy,
    authorizeSqlOperation: authorizeSqlOperation,
    authorizationStageBudget: const Duration(seconds: 3),
    onPermissionDenied: MetricsCollector().recordRemotePermissionDenied,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      QueryRequest(
        id: 'test',
        agentId: 'test',
        query: 'SELECT 1',
        timestamp: DateTime.now(),
      ),
    );
    registerFallbackValue(
      QueryResponse(
        id: 'test',
        requestId: 'test',
        agentId: 'test',
        data: const [],
        timestamp: DateTime.now(),
      ),
    );
    registerFallbackValue(
      const AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-1',
      ),
    );
    registerFallbackValue(
      RpcResponse.success(id: 'fallback', result: const <String, dynamic>{}),
    );
    registerFallbackValue(
      AgentActionRemoteAuditRecord(
        id: 'fallback-audit',
        occurredAtUtc: DateTime.utc(2026),
        rpcMethod: 'agent.action.run',
        outcome: 'success',
        credentialPresent: false,
      ),
    );
  });

  group('RpcMethodDispatcher agent.action.*', () {
    late MockDatabaseGateway mockGateway;
    late MockQueryNormalizerService mockNormalizer;
    late MockOdbcNativeMetricsService mockOdbcNativeMetricsService;
    late MockFeatureFlags mockFeatureFlags;
    late MockRunAgentActionLocally mockRun;
    late MockRunAgentActionViaRemoteTrigger mockRemoteRun;
    late MockCancelAgentActionExecution mockCancel;
    late MockGetAgentActionExecution mockGetExecution;
    late MockSliceAgentActionCapturedOutput mockSliceCapturedOutput;
    late MockGetAgentActionDefinition mockGetDefinition;
    late MockAuthorizeSqlOperation mockAuthorize;
    late MockGetClientTokenPolicy mockGetPolicy;
    late RpcMethodDispatcher dispatcher;

    setUp(() {
      mockGateway = MockDatabaseGateway();
      mockNormalizer = MockQueryNormalizerService();
      mockOdbcNativeMetricsService = MockOdbcNativeMetricsService();
      mockFeatureFlags = MockFeatureFlags();
      mockRun = MockRunAgentActionLocally();
      mockRemoteRun = MockRunAgentActionViaRemoteTrigger();
      mockCancel = MockCancelAgentActionExecution();
      mockGetExecution = MockGetAgentActionExecution();
      mockSliceCapturedOutput = MockSliceAgentActionCapturedOutput();
      mockGetDefinition = MockGetAgentActionDefinition();
      mockAuthorize = MockAuthorizeSqlOperation();
      mockGetPolicy = MockGetClientTokenPolicy();

      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketCancelMethod).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(false);
      when(() => mockFeatureFlags.enableDashboardSqlInvestigationFeed).thenReturn(false);
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(false);
      when(() => mockFeatureFlags.enableAgentActions).thenReturn(true);
      when(() => mockFeatureFlags.enableRemoteAgentActions).thenReturn(true);
      when(() => mockFeatureFlags.enableAgentActionsMaintenanceMode).thenReturn(false);
      when(() => mockFeatureFlags.enableRemoteAdHocAgentActions).thenReturn(false);

      when(() => mockGetPolicy(any())).thenAnswer(
        (_) async => const Success(
          ClientTokenPolicy(
            clientId: 'default-client',
            allTables: false,
            allViews: false,
            rules: [],
          ),
        ),
      );
      when(
        () => mockAuthorize(
          token: any(named: 'token'),
          sql: any(named: 'sql'),
          requestDatabase: any(named: 'requestDatabase'),
          requestId: any(named: 'requestId'),
          method: any(named: 'method'),
        ),
      ).thenAnswer((_) async => const Success(unit));
      when(() => mockGetDefinition(any())).thenAnswer(
        (_) async => const Success(
          AgentActionDefinition(
            id: 'action-1',
            name: 'Action',
            state: AgentActionState.active,
            config: CommandLineActionConfig(command: 'dir'),
          ),
        ),
      );

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
          maxCallsPerMinute: 0,
        ),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        sliceAgentActionCapturedOutput: mockSliceCapturedOutput,
        getAgentActionDefinition: mockGetDefinition,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
      );
    });

    test('should route every published agent.action RPC method without method_not_found', () async {
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer(
        (_) async => Failure(
          ActionValidationFailure.withContext(message: 'stub remote run'),
        ),
      );
      when(() => mockRun.validateRemoteRun(any())).thenAnswer(
        (_) async => Failure(
          ActionValidationFailure.withContext(message: 'stub validate run'),
        ),
      );
      when(() => mockCancel(any())).thenAnswer(
        (_) async => Failure(
          ActionValidationFailure.withContext(message: 'stub cancel'),
        ),
      );
      when(
        () => mockGetExecution(
          any(),
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        ),
      ).thenAnswer(
        (_) async => Failure(
          ActionValidationFailure.withContext(message: 'stub get execution'),
        ),
      );

      const publishedParams = <String, Map<String, dynamic>>{
        AgentActionRpcConstants.agentActionRunRpcMethodName: <String, dynamic>{
          'action_id': 'action-1',
          'idempotency_key': 'idem-route',
        },
        AgentActionRpcConstants.agentActionValidateRunRpcMethodName: <String, dynamic>{
          'action_id': 'action-1',
          'idempotency_key': 'idem-route',
        },
        AgentActionRpcConstants.agentActionCancelRpcMethodName: <String, dynamic>{
          'execution_id': 'exec-route',
        },
        AgentActionRpcConstants.agentActionGetExecutionRpcMethodName: <String, dynamic>{
          'execution_id': 'exec-route',
        },
      };

      for (final method in AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered) {
        final response = await dispatcher.dispatch(
          RpcRequest(
            jsonrpc: '2.0',
            method: method,
            id: 'route-$method',
            params: publishedParams[method] ?? const <String, dynamic>{},
          ),
          'agent-1',
        );

        expect(
          response.error?.code,
          isNot(equals(RpcErrorCode.methodNotFound)),
        );
      }
    });

    test('should return temporarily unavailable when agent actions feature flag is disabled', () async {
      when(() => mockFeatureFlags.enableAgentActions).thenReturn(false);

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          id: 51,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem',
          },
        ),
        'agent-1',
      );

      check(response.error).isNotNull();
      check(response.error!.code).equals(RpcErrorCode.agentActionsTemporarilyUnavailable);
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should return temporarily unavailable when maintenance mode is enabled', () async {
      when(() => mockFeatureFlags.enableAgentActionsMaintenanceMode).thenReturn(true);

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 52,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem',
          },
        ),
        'agent-1',
      );

      check(response.error).isNotNull();
      check(response.error!.code).equals(RpcErrorCode.agentActionsTemporarilyUnavailable);
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(AgentActionRpcConstants.agentActionsMaintenanceModeErrorReason);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should record authorization_denied in remote audit when remote agent actions disabled', () async {
      final mockAudit = MockAgentActionRemoteAuditStore();
      when(() => mockAudit.append(any())).thenAnswer((_) async {});
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
      when(() => mockFeatureFlags.enableRemoteAgentActions).thenReturn(false);

      final dispatcherWithAudit = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        agentActionRemoteAuditStore: mockAudit,
      );

      await dispatcherWithAudit.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 905,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-remote-off',
          },
        ),
        'agent-1',
      );

      final records = verify(() => mockAudit.append(captureAny())).captured.cast<AgentActionRemoteAuditRecord>();
      check(records.length).equals(2);
      check(records.last.outcome).equals(AgentActionRemoteAuditConstants.outcomeAuthorizationDenied);
      check(records.last.reasonCode).equals(AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should return unauthorized when remote agent actions feature flag is disabled', () async {
      when(() => mockFeatureFlags.enableRemoteAgentActions).thenReturn(false);

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 50,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem',
          },
        ),
        'agent-1',
      );

      check(response.error).isNotNull();
      check(response.error!.code).equals(RpcErrorCode.unauthorized);
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should reject agent.action.* JSON-RPC notifications without id', () async {
      final cases = <({String method, Map<String, dynamic> params})>[
        (
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          params: <String, dynamic>{'action_id': 'action-1', 'idempotency_key': 'idem-1'},
        ),
        (
          method: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          params: <String, dynamic>{'action_id': 'action-1'},
        ),
        (
          method: AgentActionRpcConstants.agentActionCancelRpcMethodName,
          params: <String, dynamic>{'execution_id': 'exec-1'},
        ),
        (
          method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          params: <String, dynamic>{'execution_id': 'exec-1'},
        ),
      ];

      for (final (:method, :params) in cases) {
        final response = await dispatcher.dispatch(
          RpcRequest(
            jsonrpc: '2.0',
            method: method,
            id: null,
            params: params,
          ),
          'agent-1',
        );

        check(response.id).isNull();
        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.invalidParams);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason);
      }

      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
      verifyNever(() => mockCancel(any()));
      verifyNever(() => mockGetExecution(
          any(),
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        ));
    });

    test('should record notification rejected metric without remote rpc error counter', () async {
      final metrics = MetricsCollector();
      final metricsBridge = RpcDispatchMetricsCollector(metrics);
      final metricsDispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        dispatchMetrics: metricsBridge,
      );

      await metricsDispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: null,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
          },
        ),
        'agent-1',
      );

      final snapshot = metrics.getSnapshot();
      expect(snapshot['rpc_remote_agent_action_run_notification_rejected'], 1);
      expect(snapshot['rpc_remote_agent_action_run_error'], isNull);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should reject agent.action.run when subsystem is draining before use case', () async {
      final guard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');
      final drainingDispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        agentActionRuntimeStateGuard: guard,
      );

      final response = await drainingDispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 52,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem',
          },
        ),
        'agent-1',
      );

      check(response.error).isNotNull();
      check(response.error!.code).equals(RpcErrorCode.agentActionsTemporarilyUnavailable);
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(AgentActionRuntimeStateConstants.agentActionsDrainingReason);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should append remote audit for rejected agent.action.run notification', () async {
      final mockAudit = MockAgentActionRemoteAuditStore();
      when(() => mockAudit.append(any())).thenAnswer((_) async {});
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);

      const runtimeIdentity = AgentRuntimeIdentity(
        runtimeInstanceId: 'inst-notify-test',
        runtimeSessionId: 'sess-notify-test',
      );
      final dispatcherWithAudit = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        agentActionRemoteAuditStore: mockAudit,
        agentRuntimeIdentity: runtimeIdentity,
      );

      final response = await dispatcherWithAudit.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: null,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
          },
        ),
        'agent-1',
      );

      check(response.id).isNull();
      check(response.error).isNotNull();
      final captured = verify(() => mockAudit.append(captureAny()));
      captured.called(2);
      final records = captured.captured.cast<AgentActionRemoteAuditRecord>().toList();
      check(records.first.outcome).equals(AgentActionRemoteAuditConstants.outcomeReceived);
      final record = records.last;
      check(record.rpcMethod).equals(AgentActionRpcConstants.agentActionRunRpcMethodName);
      check(record.outcome).equals(AgentActionRemoteAuditConstants.outcomeNotificationRejected);
      check(record.actionId).equals('action-1');
      check(record.runtimeInstanceId).equals('inst-notify-test');
      check(record.runtimeSessionId).equals('sess-notify-test');
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should append remote audit with client id for rejected notification when token resolves', () async {
      final mockAudit = MockAgentActionRemoteAuditStore();
      when(() => mockAudit.append(any())).thenAnswer((_) async {});
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
      when(() => mockGetPolicy('tok-notify')).thenAnswer(
        (_) async => const Success(
          ClientTokenPolicy(
            clientId: 'notify-audit-client',
            tokenId: 'notify-audit-jti',
            allTables: false,
            allViews: false,
            rules: [],
          ),
        ),
      );

      final dispatcherWithAudit = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        agentActionRemoteAuditStore: mockAudit,
      );

      await dispatcherWithAudit.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: null,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
            'client_token': 'tok-notify',
          },
        ),
        'agent-1',
        clientToken: 'tok-notify',
      );

      final captured = verify(() => mockAudit.append(captureAny()));
      captured.called(2);
      final records = captured.captured.cast<AgentActionRemoteAuditRecord>().toList();
      check(records.last.clientId).equals('notify-audit-client');
      check(records.last.tokenJti).equals('notify-audit-jti');
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    test('should route agent.action.run to RunAgentActionViaRemoteTrigger', () async {
      final execution = AgentActionExecution(
        id: 'exec-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-1',
        requestedBy: 'remote',
        traceId: 'trace-1',
        triggerId: 'trigger-remote-1',
        triggerType: AgentActionTriggerType.remote,
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 1,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
            'trigger_id': 'trigger-remote-1',
          },
          meta: RpcProtocolMeta(traceId: 'trace-1', requestId: 'hub-req-1'),
        ),
        'agent-1',
      );

      check(response.error).isNull();
      check(response.result).isNotNull();
      final result = response.result! as Map<String, dynamic>;
      check(result['execution_id']).equals('exec-1');
      check(result['status']).equals('queued');

      final captured = verify(
        () => mockRemoteRun(
          actionId: 'action-1',
          idempotencyKey: 'idem-1',
          triggerId: 'trigger-remote-1',
          requestedBy: 'hub-req-1',
          traceId: 'trace-1',
        ),
      );
      captured.called(1);
    });

    test('should route agent.action.validateRun to validateRemoteRun', () async {
      const summary = AgentActionValidateRunSummary(
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        definitionSnapshotHash: 'sha256:abc',
      );
      when(() => mockRun.validateRemoteRun(any())).thenAnswer((_) async => const Success(summary));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          id: 2,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
          },
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final result = response.result! as Map<String, dynamic>;
      check(result['valid']).equals(true);
      check(result['action_id']).equals('action-1');
      verify(() => mockRun.validateRemoteRun(any())).called(1);
    });

    test('should route agent.action.cancel', () async {
      final execution = AgentActionExecution(
        id: 'exec-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.cancelled,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 1),
        redactionApplied: true,
        failureCode: AgentActionFailureCode.queueCancelled,
        failurePhase: 'queue',
        failureMessage: 'cancelled',
      );
      when(() => mockCancel(any())).thenAnswer((_) async => Success(execution));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionCancelRpcMethodName,
          id: 3,
          params: <String, dynamic>{'execution_id': 'exec-1'},
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final result = response.result! as Map<String, dynamic>;
      check(result['cancelled']).equals(true);
      check(result['execution_id']).equals('exec-1');
      verify(() => mockCancel('exec-1')).called(1);
    });

    test('should route agent.action.getExecution', () async {
      final execution = AgentActionExecution(
        id: 'exec-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        redactionApplied: true,
      );
      when(() => mockGetExecution(
          any(),
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        )).thenAnswer((_) async => Success(execution));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          id: 4,
          params: <String, dynamic>{
            'execution_id': 'exec-1',
            'max_output_bytes': 1024,
          },
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final result = response.result! as Map<String, dynamic>;
      check(result['execution_id']).equals('exec-1');
      check(result['status']).equals('succeeded');
      verify(
        () => mockGetExecution('exec-1', hydrateCapturedOutput: false),
      ).called(1);
    });

    test('should hide stdout when include_output is false', () async {
      final execution = AgentActionExecution(
        id: 'exec-no-output',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        stdoutText: 'should-not-appear',
        redactionApplied: true,
      );
      when(
        () => mockGetExecution(
          'exec-no-output',
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        ),
      ).thenAnswer((_) async => Success(execution));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          id: 42,
          params: <String, dynamic>{
            'execution_id': 'exec-no-output',
            'include_output': false,
          },
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final stdout = ((response.result! as Map<String, dynamic>)['output'] as Map<String, dynamic>)['stdout']
          as Map<String, dynamic>;
      check(stdout['captured']).equals(false);
      check(stdout.containsKey('text')).equals(false);
    });

    test('should hide stdout when capture policy disables stdout', () async {
      const definition = AgentActionDefinition(
        id: 'action-1',
        name: 'Action',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          capture: AgentActionCapturePolicy(captureStdout: false),
        ),
      );
      final execution = AgentActionExecution(
        id: 'exec-policy',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        stdoutText: 'stored-but-policy-hidden',
        stderrText: 'stderr-visible',
        redactionApplied: true,
      );
      when(
        () => mockGetExecution(
          'exec-policy',
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        ),
      ).thenAnswer((_) async => Success(execution));
      when(() => mockGetDefinition('action-1')).thenAnswer((_) async => const Success(definition));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          id: 43,
          params: <String, dynamic>{'execution_id': 'exec-policy'},
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final output = (response.result! as Map<String, dynamic>)['output'] as Map<String, dynamic>;
      final stdout = output['stdout'] as Map<String, dynamic>;
      final stderr = output['stderr'] as Map<String, dynamic>;
      check(stdout['captured']).equals(false);
      check(stderr['captured']).equals(true);
      check(stderr['text']).equals('stderr-visible');
    });

    test('should page redacted stdout in agent.action.getExecution result', () async {
      final stdout = 'a' * 200;
      final execution = AgentActionExecution(
        id: 'exec-page',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        stdoutText: stdout,
        redactionApplied: true,
      );
      when(
        () => mockGetExecution(
          'exec-page',
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        ),
      ).thenAnswer((_) async => Success(execution));

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          id: 41,
          params: <String, dynamic>{
            'execution_id': 'exec-page',
            'stdout_offset': 0,
            'max_output_bytes': 50,
          },
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final output = (response.result! as Map<String, dynamic>)['output'] as Map<String, dynamic>;
      final stdoutMap = output['stdout'] as Map<String, dynamic>;
      check(stdoutMap['captured']).equals(true);
      check(stdoutMap['response_truncated']).equals(true);
      check((stdoutMap['text'] as String).length).equals(50);
      check(stdoutMap['next_offset']).equals(50);
      check(stdoutMap['utf8_total_bytes']).equals(200);
    });

    test('should page stdout from chunks via slice without hydrating on getExecution', () async {
      final stdout = 'b' * 200;
      final execution = AgentActionExecution(
        id: 'exec-chunk-page',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        stdoutStoredInChunks: true,
        redactionApplied: true,
      );
      when(
        () => mockGetExecution(
          'exec-chunk-page',
          hydrateCapturedOutput: false,
        ),
      ).thenAnswer((_) async => Success(execution));
      when(
        () => mockSliceCapturedOutput(
          executionId: 'exec-chunk-page',
          stream: AgentActionCapturedOutputConstants.stdoutStream,
          offsetUtf8: 0,
          maxBytes: 50,
        ),
      ).thenAnswer(
        (_) async => Success(
          (
            text: stdout.substring(0, 50),
            nextOffset: 50,
            totalBytes: 200,
            responseTruncated: true,
            effectiveStart: 0,
          ),
        ),
      );

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          id: 42,
          params: <String, dynamic>{
            'execution_id': 'exec-chunk-page',
            'stdout_offset': 0,
            'max_output_bytes': 50,
          },
        ),
        'agent-1',
      );

      check(response.error).isNull();
      final output = (response.result! as Map<String, dynamic>)['output'] as Map<String, dynamic>;
      final stdoutMap = output['stdout'] as Map<String, dynamic>;
      check(stdoutMap['captured']).equals(true);
      check(stdoutMap['response_truncated']).equals(true);
      check((stdoutMap['text'] as String).length).equals(50);
      verify(
        () => mockSliceCapturedOutput(
          executionId: 'exec-chunk-page',
          stream: AgentActionCapturedOutputConstants.stdoutStream,
          offsetUtf8: 0,
          maxBytes: 50,
        ),
      ).called(1);
      verifyNever(
        () => mockGetExecution(
          'exec-chunk-page',
        ),
      );
    });

    test('should derive trace id from W3C traceparent when meta.trace_id is absent', () async {
      final execution = AgentActionExecution(
        id: 'exec-tp',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-tp',
        requestedBy: '99',
        traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 99,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-tp',
          },
          meta: RpcProtocolMeta(
            traceParent: '00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-1234567890123456-01',
          ),
        ),
        'agent-1',
      );

      verify(
        () => mockRemoteRun(
          actionId: 'action-1',
          idempotencyKey: 'idem-tp',
          triggerId: any(named: 'triggerId'),
          requestedBy: '99',
          traceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ).called(1);
    });

    test('should prefer params.trace_id over meta.trace_id', () async {
      final execution = AgentActionExecution(
        id: 'exec-params-trace',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-params-trace',
        requestedBy: 'hub-operator',
        traceId: 'trace-from-params',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 101,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-params-trace',
            'trace_id': 'trace-from-params',
            'requested_by': 'hub-operator',
          },
          meta: RpcProtocolMeta(
            traceId: 'meta-trace-should-lose',
          ),
        ),
        'agent-1',
      );

      verify(
        () => mockRemoteRun(
          actionId: 'action-1',
          idempotencyKey: 'idem-params-trace',
          triggerId: any(named: 'triggerId'),
          requestedBy: 'hub-operator',
          traceId: 'trace-from-params',
        ),
      ).called(1);
    });

    test('should prefer meta.trace_id over traceparent', () async {
      final execution = AgentActionExecution(
        id: 'exec-pref',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-pref',
        requestedBy: 'remote',
        traceId: 'hub-trace-override',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 100,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-pref',
          },
          meta: RpcProtocolMeta(
            traceId: 'hub-trace-override',
            traceParent: '00-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-1234567890123456-01',
          ),
        ),
        'agent-1',
      );

      verify(
        () => mockRemoteRun(
          actionId: 'action-1',
          idempotencyKey: 'idem-pref',
          triggerId: any(named: 'triggerId'),
          requestedBy: '100',
          traceId: 'hub-trace-override',
        ),
      ).called(1);
    });

    test('should use meta.agent_id as requestedBy when request_id is absent', () async {
      final execution = AgentActionExecution(
        id: 'exec-agent',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-agent',
        requestedBy: 'hub-agent-xyz',
        traceId: 't1',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 101,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-agent',
          },
          meta: RpcProtocolMeta(traceId: 't1', agentId: 'hub-agent-xyz'),
        ),
        'agent-1',
      );

      verify(
        () => mockRemoteRun(
          actionId: 'action-1',
          idempotencyKey: 'idem-agent',
          triggerId: any(named: 'triggerId'),
          requestedBy: 'hub-agent-xyz',
          traceId: 't1',
        ),
      ).called(1);
    });

    test('should fall back requestedBy to jsonrpc id when meta request_id and agent_id absent', () async {
      final execution = AgentActionExecution(
        id: 'exec-id',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-id',
        requestedBy: '202',
        traceId: 't2',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 202,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-id',
          },
          meta: RpcProtocolMeta(traceId: 't2'),
        ),
        'agent-1',
      );

      verify(
        () => mockRemoteRun(
          actionId: 'action-1',
          idempotencyKey: 'idem-id',
          triggerId: any(named: 'triggerId'),
          requestedBy: '202',
          traceId: 't2',
        ),
      ).called(1);
    });

    test('should persist agent.action.run RPC idempotency under method-scoped store key when enabled', () async {
      final mockStore = MockIdempotencyStore();
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
          maxCallsPerMinute: 0,
        ),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        idempotencyStore: mockStore,
      );

      final execution = AgentActionExecution(
        id: 'exec-rpc-idem',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-rpc',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));
      when(() => mockStore.getRecord(any())).thenAnswer((_) async => null);
      when(
        () => mockStore.set(
          any(),
          any(),
          ConnectionConstants.agentActionRpcIdempotencyEntryTtl,
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).thenAnswer((_) async {});

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 501,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-rpc',
          },
        ),
        'agent-1',
      );

      verify(
        () => mockStore.set(
          '${AgentActionRpcConstants.agentActionRunRpcMethodName}:idem-rpc',
          any(),
          ConnectionConstants.agentActionRpcIdempotencyEntryTtl,
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).called(1);
    });

    test('should use AgentActionRetentionSettings ttl for agent.action.run idempotency cache', () async {
      final mockStore = MockIdempotencyStore();
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);
      final retentionSettings = AgentActionRetentionSettings(InMemoryAppSettingsStore());
      await retentionSettings.save(
        executionDays: 1,
        remoteAuditDays: 30,
        capturedOutputHours: 12,
      );
      final expectedTtl = retentionSettings.agentActionRpcIdempotencyTtl;

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
          maxCallsPerMinute: 0,
        ),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        idempotencyStore: mockStore,
        agentActionRetentionSettings: retentionSettings,
      );

      final execution = AgentActionExecution(
        id: 'exec-rpc-idem-retention',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 19, 12),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-retention',
        queueStartedAt: DateTime.utc(2026, 5, 19, 12),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));
      when(() => mockStore.getRecord(any())).thenAnswer((_) async => null);
      when(
        () => mockStore.set(
          any(),
          any(),
          expectedTtl,
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).thenAnswer((_) async {});

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 502,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-retention',
          },
        ),
        'agent-1',
      );

      verify(
        () => mockStore.set(
          '${AgentActionRpcConstants.agentActionRunRpcMethodName}:idem-retention',
          any(),
          expectedTtl,
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).called(1);
      check(expectedTtl).equals(const Duration(days: 1));
    });

    test('should replay agent.action.run from RPC idempotency cache without second runner call', () async {
      final mockStore = MockIdempotencyStore();
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
          maxCallsPerMinute: 0,
        ),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        idempotencyStore: mockStore,
      );

      final execution = AgentActionExecution(
        id: 'exec-replay',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-replay-rpc',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      RpcResponse? storedSuccess;
      when(() => mockStore.getRecord(any())).thenAnswer((_) async {
        if (storedSuccess == null) {
          return null;
        }
        return IdempotencyRecord(
          response: storedSuccess!,
          requestFingerprint: null,
        );
      });
      when(
        () => mockStore.set(
          any(),
          any(),
          ConnectionConstants.agentActionRpcIdempotencyEntryTtl,
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).thenAnswer((Invocation invocation) async {
        storedSuccess = invocation.positionalArguments[1] as RpcResponse;
      });

      const params = <String, dynamic>{
        'action_id': 'action-1',
        'idempotency_key': 'idem-replay-rpc',
      };

      final first = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 601,
          params: params,
        ),
        'agent-1',
      );

      final second = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 602,
          params: params,
        ),
        'agent-1',
      );

      check(first.isSuccess).isTrue();
      check(second.isSuccess).isTrue();
      check(second.id).equals(602);
      check(second.result).equals(first.result);
      verify(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).called(1);
    });

    test('should reject agent.action.run when idempotency_key reuses different payload fingerprint', () async {
      final mockStore = MockIdempotencyStore();
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        idempotencyStore: mockStore,
      );

      when(() => mockStore.getRecord(any())).thenAnswer(
        (_) async => IdempotencyRecord(
          response: RpcResponse.success(
            id: 1,
            result: <String, dynamic>{'execution_id': 'exec-prior'},
          ),
          requestFingerprint: 'fingerprint-action-a',
        ),
      );

      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 603,
          params: <String, dynamic>{
            'action_id': 'action-2',
            'idempotency_key': 'idem-shared',
          },
        ),
        'agent-1',
      );

      check(response.error).isNotNull();
      check(response.error!.code).equals(RpcErrorCode.invalidParams);
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason);
      check(data['category']).equals(RpcErrorCode.categoryAction);
      verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
    });

    group('runner failure RPC mapping', () {
      Future<RpcResponse> dispatchRun() {
        return dispatcher.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 700,
            params: <String, dynamic>{
              'action_id': 'action-gate-1',
              'idempotency_key': 'idem-gate-1',
            },
          ),
          'agent-1',
        );
      }

      test('should map remote not approved to unauthorized with stable reason', () async {
        when(
          () => mockRemoteRun(
            actionId: any(named: 'actionId'),
            idempotencyKey: any(named: 'idempotencyKey'),
            triggerId: any(named: 'triggerId'),
            requestedBy: any(named: 'requestedBy'),
            traceId: any(named: 'traceId'),
          ),
        ).thenAnswer(
          (_) async => Failure(
            ActionAuthorizationFailure.withContext(
              message: 'Action is not approved for remote execution.',
              code: AgentActionFailureCode.remoteNotApproved,
              context: const {
                'reason': AgentActionGateConstants.remoteActionNotApprovedReason,
              },
            ),
          ),
        );

        final response = await dispatchRun();

        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.unauthorized);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(AgentActionGateConstants.remoteActionNotApprovedReason);
        check(data['category']).equals(RpcErrorCode.categoryAction);
      });

      test('should map environment profile denied to unauthorized with stable reason', () async {
        when(
          () => mockRemoteRun(
            actionId: any(named: 'actionId'),
            idempotencyKey: any(named: 'idempotencyKey'),
            triggerId: any(named: 'triggerId'),
            requestedBy: any(named: 'requestedBy'),
            traceId: any(named: 'traceId'),
          ),
        ).thenAnswer(
          (_) async => Failure(
            ActionAuthorizationFailure.withContext(
              message: 'Action is not allowed in the current agent operational profile.',
              code: AgentActionFailureCode.environmentProfileDenied,
              context: const {
                'reason': AgentActionGateConstants.environmentProfileDeniedReason,
                'current_profile': 'development',
              },
            ),
          ),
        );

        final response = await dispatchRun();

        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.unauthorized);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(AgentActionGateConstants.environmentProfileDeniedReason);
        check(data['category']).equals(RpcErrorCode.categoryAction);
        check(data['current_profile']).equals('development');
      });

      test('should map secret unavailable to invalidParams with stable reason', () async {
        when(
          () => mockRemoteRun(
            actionId: any(named: 'actionId'),
            idempotencyKey: any(named: 'idempotencyKey'),
            triggerId: any(named: 'triggerId'),
            requestedBy: any(named: 'requestedBy'),
            traceId: any(named: 'traceId'),
          ),
        ).thenAnswer(
          (_) async => Failure(
            ActionValidationFailure.withContext(
              message: 'Referenced action secrets are not available.',
              code: AgentActionFailureCode.secretUnavailable,
              context: const {
                'reason': AgentActionGateConstants.secretUnavailableReason,
                'missing_secrets': <String>['api_token'],
              },
            ),
          ),
        );

        final response = await dispatchRun();

        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.invalidParams);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(AgentActionGateConstants.secretUnavailableReason);
        check(data['category']).equals(RpcErrorCode.categoryAction);
        check(data.containsKey('missing_secrets')).isFalse();
      });
    });

    test('should replay agent.action.run when only trace_id differs in params', () async {
      final mockStore = MockIdempotencyStore();
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        healthService: _healthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetPolicy,
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
          maxCallsPerMinute: 0,
        ),
        featureFlags: mockFeatureFlags,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
        runAgentActionLocally: mockRun,
        runAgentActionViaRemoteTrigger: mockRemoteRun,
        cancelAgentActionExecution: mockCancel,
        getAgentActionExecution: mockGetExecution,
        agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
        agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
          featureFlags: mockFeatureFlags,
          getClientTokenPolicy: mockGetPolicy,
          authorizeSqlOperation: mockAuthorize,
        ),
        idempotencyStore: mockStore,
      );

      final execution = AgentActionExecution(
        id: 'exec-replay-trace',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-replay-trace',
        queueStartedAt: DateTime.utc(2026, 5, 18, 14),
        redactionApplied: true,
      );
      when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

      RpcResponse? storedSuccess;
      when(() => mockStore.getRecord(any())).thenAnswer((_) async {
        if (storedSuccess == null) {
          return null;
        }
        return IdempotencyRecord(
          response: storedSuccess!,
          requestFingerprint: null,
        );
      });
      when(
        () => mockStore.set(
          any(),
          any(),
          ConnectionConstants.agentActionRpcIdempotencyEntryTtl,
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).thenAnswer((Invocation invocation) async {
        storedSuccess = invocation.positionalArguments[1] as RpcResponse;
      });

      await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 701,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-replay-trace',
            'trace_id': 'trace-a',
          },
        ),
        'agent-1',
      );

      final second = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 702,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-replay-trace',
            'trace_id': 'trace-b',
          },
        ),
        'agent-1',
      );

      check(second.isSuccess).isTrue();
      verify(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).called(1);
    });

    group('client token policy scopes', () {
      test('should return unauthorized when client token is missing and auth is required', () async {
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);

        final response = await dispatcher.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 899,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-no-token',
            },
          ),
          'agent-1',
        );

        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.authenticationFailed);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(RpcClientTokenConstants.missingClientTokenReason);
        verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
        verifyNever(() => mockGetPolicy(any()));
      });

      test('should return unauthorized when policy declares scopes without run', () async {
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        when(() => mockGetPolicy(any())).thenAnswer(
          (_) async => const Success(
            ClientTokenPolicy(
              clientId: 'c1',
              allTables: false,
              allViews: false,
              rules: [],
              payload: <String, dynamic>{
                'agent_actions': <String, dynamic>{
                  'scopes': <String>[AgentActionRpcConstants.agentActionsValidateRunScope],
                },
              },
            ),
          ),
        );

        final execution = AgentActionExecution(
          id: 'e1',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem',
          queueStartedAt: DateTime.utc(2026, 5, 18, 14),
          redactionApplied: true,
        );
        when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

        final response = await dispatcher.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 900,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem',
            },
          ),
          'agent-1',
          clientToken: 'tok',
        );

        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.unauthorized);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(AgentActionRpcConstants.agentActionPermissionDeniedErrorReason);
        check(data['required_scope']).equals(AgentActionRpcConstants.agentActionsRunScope);
        check(data['action_id']).equals('action-1');
        verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
      });

      test('should record authorization_denied in remote audit when client token is missing', () async {
        final mockAudit = MockAgentActionRemoteAuditStore();
        when(() => mockAudit.append(any())).thenAnswer((_) async {});
        when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);

        final dispatcherWithAudit = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthService(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          getClientTokenPolicy: mockGetPolicy,
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
          featureFlags: mockFeatureFlags,
          odbcNativeMetricsService: mockOdbcNativeMetricsService,
          runAgentActionLocally: mockRun,
          runAgentActionViaRemoteTrigger: mockRemoteRun,
          cancelAgentActionExecution: mockCancel,
          getAgentActionExecution: mockGetExecution,
          agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
          agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
            featureFlags: mockFeatureFlags,
            getClientTokenPolicy: mockGetPolicy,
            authorizeSqlOperation: mockAuthorize,
          ),
          agentActionRemoteAuditStore: mockAudit,
        );

        await dispatcherWithAudit.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 904,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-no-token-audit',
              'trace_id': 'trace-missing-token',
            },
          ),
          'agent-1',
        );

        final records = verify(() => mockAudit.append(captureAny())).captured.cast<AgentActionRemoteAuditRecord>();
        check(records.length).equals(2);
        check(records.first.outcome).equals(AgentActionRemoteAuditConstants.outcomeReceived);
        check(records.first.credentialPresent).isFalse();
        check(records.first.traceId).equals('trace-missing-token');
        check(records.last.outcome).equals(AgentActionRemoteAuditConstants.outcomeAuthorizationDenied);
        check(records.last.reasonCode).equals(RpcClientTokenConstants.missingClientTokenReason);
        check(records.last.credentialPresent).isFalse();
        check(records.last.clientId).isNull();
        verifyNever(() => mockGetPolicy(any()));
      });

      test('should record idempotency_key in remote audit for agent.action.run', () async {
        final mockAudit = MockAgentActionRemoteAuditStore();
        when(() => mockAudit.append(any())).thenAnswer((_) async {});
        when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);

        final execution = AgentActionExecution(
          id: 'exec-idem-audit',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-audit-1',
          queueStartedAt: DateTime.utc(2026, 5, 18, 14),
          redactionApplied: true,
        );
        when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

        final dispatcherWithAudit = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthService(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          getClientTokenPolicy: mockGetPolicy,
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
          featureFlags: mockFeatureFlags,
          odbcNativeMetricsService: mockOdbcNativeMetricsService,
          runAgentActionLocally: mockRun,
          runAgentActionViaRemoteTrigger: mockRemoteRun,
          cancelAgentActionExecution: mockCancel,
          getAgentActionExecution: mockGetExecution,
          agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
          agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
            featureFlags: mockFeatureFlags,
            getClientTokenPolicy: mockGetPolicy,
            authorizeSqlOperation: mockAuthorize,
          ),
          agentActionRemoteAuditStore: mockAudit,
        );

        await dispatcherWithAudit.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 908,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-audit-1',
            },
          ),
          'agent-1',
        );

        final records = verify(() => mockAudit.append(captureAny())).captured.cast<AgentActionRemoteAuditRecord>();
        check(records.length).equals(2);
        check(records.first.idempotencyKey).equals('idem-audit-1');
        check(records.last.idempotencyKey).equals('idem-audit-1');
      });

      test('should record authorization_denied in remote audit when scope denied', () async {
        final mockAudit = MockAgentActionRemoteAuditStore();
        when(() => mockAudit.append(any())).thenAnswer((_) async {});
        when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        when(() => mockGetPolicy(any())).thenAnswer(
          (_) async => const Success(
            ClientTokenPolicy(
              clientId: 'deny-client',
              tokenId: 'deny-jti',
              allTables: false,
              allViews: false,
              rules: [],
              payload: <String, dynamic>{
                'agent_actions': <String, dynamic>{
                  'scopes': <String>[AgentActionRpcConstants.agentActionsCancelScope],
                },
              },
            ),
          ),
        );

        final dispatcherWithAudit = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthService(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          getClientTokenPolicy: mockGetPolicy,
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
          featureFlags: mockFeatureFlags,
          odbcNativeMetricsService: mockOdbcNativeMetricsService,
          runAgentActionLocally: mockRun,
          runAgentActionViaRemoteTrigger: mockRemoteRun,
          cancelAgentActionExecution: mockCancel,
          getAgentActionExecution: mockGetExecution,
          agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
          agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
            featureFlags: mockFeatureFlags,
            getClientTokenPolicy: mockGetPolicy,
            authorizeSqlOperation: mockAuthorize,
          ),
          agentActionRemoteAuditStore: mockAudit,
        );

        await dispatcherWithAudit.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 905,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-deny-audit',
            },
          ),
          'agent-1',
          clientToken: 'tok',
        );

        final records = verify(() => mockAudit.append(captureAny())).captured.cast<AgentActionRemoteAuditRecord>();
        check(records.length).equals(2);
        check(records.first.outcome).equals(AgentActionRemoteAuditConstants.outcomeReceived);
        check(records.last.outcome).equals(AgentActionRemoteAuditConstants.outcomeAuthorizationDenied);
        check(records.last.clientId).equals('deny-client');
        check(records.last.tokenJti).equals('deny-jti');
        check(records.last.actionId).equals('action-1');
      });

      test('should record rate_limited in remote audit when remote rate limit exceeded', () async {
        final mockAudit = MockAgentActionRemoteAuditStore();
        when(() => mockAudit.append(any())).thenAnswer((_) async {});
        when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);

        final execution = AgentActionExecution(
          id: 'exec-rate-1',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-rate-1',
          queueStartedAt: DateTime.utc(2026, 5, 18, 14),
          redactionApplied: true,
        );
        when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

        final metrics = MetricsCollector();
        var rateLimitedMetricInvocations = 0;
        final dispatcherWithAudit = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: HealthService(
            metricsCollector: metrics,
            gateway: mockGateway,
          ),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          getClientTokenPolicy: mockGetPolicy,
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
          featureFlags: mockFeatureFlags,
          odbcNativeMetricsService: mockOdbcNativeMetricsService,
          runAgentActionLocally: mockRun,
          runAgentActionViaRemoteTrigger: mockRemoteRun,
          cancelAgentActionExecution: mockCancel,
          getAgentActionExecution: mockGetExecution,
          agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 1),
          onAgentActionRemoteRateLimited: () {
            rateLimitedMetricInvocations++;
            metrics.recordRemoteRateLimited();
          },
          agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
            featureFlags: mockFeatureFlags,
            getClientTokenPolicy: mockGetPolicy,
            authorizeSqlOperation: mockAuthorize,
          ),
          agentActionRemoteAuditStore: mockAudit,
        );

        await dispatcherWithAudit.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 906,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-rate-1',
            },
          ),
          'agent-1',
        );

        final second = await dispatcherWithAudit.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 907,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-rate-2',
            },
          ),
          'agent-1',
        );

        check(second.error).isNotNull();
        check(second.error!.code).equals(RpcErrorCode.rateLimited);
        final data = second.error!.data as Map<String, dynamic>;
        check(data['reason']).equals(AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason);
        verify(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).called(1);

        final records = verify(() => mockAudit.append(captureAny())).captured.cast<AgentActionRemoteAuditRecord>();
        check(records.length).equals(4);
        check(records[2].outcome).equals(AgentActionRemoteAuditConstants.outcomeReceived);
        check(records.last.outcome).equals(AgentActionRemoteAuditConstants.outcomeRateLimited);
        check(records.last.reasonCode).equals(AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason);
        check(rateLimitedMetricInvocations).equals(1);
        check(metrics.getSnapshot()['agent_action_remote_rate_limited']).equals(1);
      });

      test('should invoke permission denied callback when policy denies run', () async {
        var permissionDeniedInvocations = 0;
        final dispatcherWithMetrics = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthService(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          getClientTokenPolicy: mockGetPolicy,
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
            maxCallsPerMinute: 0,
          ),
          featureFlags: mockFeatureFlags,
          odbcNativeMetricsService: mockOdbcNativeMetricsService,
          runAgentActionLocally: mockRun,
          runAgentActionViaRemoteTrigger: mockRemoteRun,
          cancelAgentActionExecution: mockCancel,
          getAgentActionExecution: mockGetExecution,
          agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
          agentActionRemoteAuthorization: AgentActionRemoteAuthorizationService(
            featureFlags: mockFeatureFlags,
            getClientTokenPolicy: mockGetPolicy,
            authorizeSqlOperation: mockAuthorize,
            authorizationStageBudget: const Duration(seconds: 3),
            onPermissionDenied: () => permissionDeniedInvocations++,
          ),
        );
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        when(() => mockGetPolicy(any())).thenAnswer(
          (_) async => const Success(
            ClientTokenPolicy(
              clientId: 'c1',
              allTables: false,
              allViews: false,
              rules: [],
              payload: <String, dynamic>{
                'agent_actions': <String, dynamic>{
                  'scopes': <String>[AgentActionRpcConstants.agentActionsValidateRunScope],
                },
              },
            ),
          ),
        );

        await dispatcherWithMetrics.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 901,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem',
            },
          ),
          'agent-1',
          clientToken: 'tok',
        );

        expect(permissionDeniedInvocations, 1);
      });

      test('should deny run when allowlist excludes action_id', () async {
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        when(() => mockGetPolicy(any())).thenAnswer(
          (_) async => const Success(
            ClientTokenPolicy(
              clientId: 'c1',
              allTables: false,
              allViews: false,
              rules: [],
              payload: <String, dynamic>{
                'agent_actions': <String, dynamic>{
                  'scopes': <String>[AgentActionRpcConstants.agentActionsRunScope],
                  'action_ids': <String>['other-action'],
                },
              },
            ),
          ),
        );

        final execution = AgentActionExecution(
          id: 'e2',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-2',
          queueStartedAt: DateTime.utc(2026, 5, 18, 14),
          redactionApplied: true,
        );
        when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

        final response = await dispatcher.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 901,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-2',
            },
          ),
          'agent-1',
          clientToken: 'tok',
        );

        check(response.error).isNotNull();
        check(response.error!.code).equals(RpcErrorCode.unauthorized);
        verifyNever(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      );
      });

      test('should call runner when token_scope grants wildcard', () async {
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        when(() => mockGetPolicy(any())).thenAnswer(
          (_) async => const Success(
            ClientTokenPolicy(
              clientId: 'c1',
              allTables: false,
              allViews: false,
              rules: [],
              payload: <String, dynamic>{
                'token_scope': AgentActionRpcConstants.agentActionsWildcardScope,
              },
            ),
          ),
        );

        final execution = AgentActionExecution(
          id: 'e3',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-3',
          queueStartedAt: DateTime.utc(2026, 5, 18, 14),
          redactionApplied: true,
        );
        when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

        final response = await dispatcher.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 902,
            params: <String, dynamic>{
              'action_id': 'action-1',
              'idempotency_key': 'idem-3',
            },
          ),
          'agent-1',
          clientToken: 'tok',
        );

        check(response.error).isNull();
        verify(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).called(1);
      });

      test('should call getExecution only once when client token auth is on', () async {
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        final execution = AgentActionExecution(
          id: 'exec-1',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.succeeded,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
          redactionApplied: true,
        );
        when(() => mockGetExecution(
          any(),
          hydrateCapturedOutput: any(named: 'hydrateCapturedOutput'),
        )).thenAnswer((_) async => Success(execution));

        final response = await dispatcher.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
            id: 903,
            params: <String, dynamic>{
              'execution_id': 'exec-1',
            },
          ),
          'agent-1',
          clientToken: 'tok',
        );

        check(response.error).isNull();
        verify(
        () => mockGetExecution('exec-1', hydrateCapturedOutput: false),
      ).called(1);
      });

      test('should append remote audit with client id and token jti from resolved policy', () async {
        final mockAudit = MockAgentActionRemoteAuditStore();
        when(() => mockAudit.append(any())).thenAnswer((_) async {});

        when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
        when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
        when(() => mockGetPolicy(any())).thenAnswer(
          (_) async => const Success(
            ClientTokenPolicy(
              clientId: 'audit-client-9',
              tokenId: 'audit-jti-7',
              allTables: false,
              allViews: false,
              rules: [],
              payload: <String, dynamic>{
                'token_scope': AgentActionRpcConstants.agentActionsWildcardScope,
              },
            ),
          ),
        );

        final execution = AgentActionExecution(
          id: 'exec-audit-1',
          actionId: 'action-audit',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: DateTime.utc(2026, 5, 18, 14),
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-audit',
          queueStartedAt: DateTime.utc(2026, 5, 18, 14),
          redactionApplied: true,
        );
        when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

        const runtimeIdentity = AgentRuntimeIdentity(
          runtimeInstanceId: 'inst-audit-test',
          runtimeSessionId: 'sess-audit-test',
        );
        var auditCorrelatedCount = 0;
        final dispatcherWithAudit = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthService(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          getClientTokenPolicy: mockGetPolicy,
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
            maxCallsPerMinute: 0,
          ),
          featureFlags: mockFeatureFlags,
          odbcNativeMetricsService: mockOdbcNativeMetricsService,
          runAgentActionLocally: mockRun,
          runAgentActionViaRemoteTrigger: mockRemoteRun,
          cancelAgentActionExecution: mockCancel,
          getAgentActionExecution: mockGetExecution,
          agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
          agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
            featureFlags: mockFeatureFlags,
            getClientTokenPolicy: mockGetPolicy,
            authorizeSqlOperation: mockAuthorize,
          ),
          agentActionRemoteAuditStore: mockAudit,
          agentRuntimeIdentity: runtimeIdentity,
          onAgentActionRemoteAuditExecutionCorrelated: () => auditCorrelatedCount++,
        );

        final response = await dispatcherWithAudit.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: AgentActionRpcConstants.agentActionRunRpcMethodName,
            id: 910,
            params: <String, dynamic>{
              'action_id': 'action-audit',
              'idempotency_key': 'idem-audit',
            },
          ),
          'agent-1',
          clientToken: 'tok-audit',
        );

      check(response.error).isNull();
      final captured = verify(() => mockAudit.append(captureAny()));
      captured.called(2);
      final records = captured.captured.cast<AgentActionRemoteAuditRecord>().toList();
      check(records.first.outcome).equals(AgentActionRemoteAuditConstants.outcomeReceived);
      final record = records.last;
      check(record.rpcMethod).equals(AgentActionRpcConstants.agentActionRunRpcMethodName);
      check(record.outcome).equals(AgentActionRemoteAuditConstants.outcomeSuccess);
      check(record.clientId).equals('audit-client-9');
      check(record.tokenJti).equals('audit-jti-7');
      check(record.credentialPresent).isTrue();
      check(record.runtimeInstanceId).equals('inst-audit-test');
      check(record.runtimeSessionId).equals('sess-audit-test');
      check(auditCorrelatedCount).equals(1);
      });

      test(
        'should append remote audit client_id when token auth is off but remote audit is on',
        () async {
          final mockAudit = MockAgentActionRemoteAuditStore();
          when(() => mockAudit.append(any())).thenAnswer((_) async {});

          when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);
          when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);
          when(() => mockGetPolicy(any())).thenAnswer(
            (_) async => const Success(
              ClientTokenPolicy(
                clientId: 'audit-auth-off-client',
                tokenId: 'audit-auth-off-jti',
                allTables: false,
                allViews: false,
                rules: [],
              ),
            ),
          );

          final execution = AgentActionExecution(
            id: 'exec-audit-auth-off',
            actionId: 'action-audit-auth-off',
            actionType: AgentActionType.commandLine,
            status: AgentActionExecutionStatus.queued,
            requestedAt: DateTime.utc(2026, 5, 18, 14),
            source: AgentActionRequestSource.remoteHub,
            idempotencyKey: 'idem-audit-auth-off',
            queueStartedAt: DateTime.utc(2026, 5, 18, 14),
            redactionApplied: true,
          );
          when(
        () => mockRemoteRun(
          actionId: any(named: 'actionId'),
          idempotencyKey: any(named: 'idempotencyKey'),
          triggerId: any(named: 'triggerId'),
          requestedBy: any(named: 'requestedBy'),
          traceId: any(named: 'traceId'),
        ),
      ).thenAnswer((_) async => Success(execution));

          final dispatcherWithAudit = RpcMethodDispatcher(
            databaseGateway: mockGateway,
            healthService: _healthService(mockGateway),
            normalizerService: mockNormalizer,
            uuid: const Uuid(),
            authorizeSqlOperation: mockAuthorize,
            getClientTokenPolicy: mockGetPolicy,
            getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
              maxCallsPerMinute: 0,
            ),
            featureFlags: mockFeatureFlags,
            odbcNativeMetricsService: mockOdbcNativeMetricsService,
            runAgentActionLocally: mockRun,
            runAgentActionViaRemoteTrigger: mockRemoteRun,
            cancelAgentActionExecution: mockCancel,
            getAgentActionExecution: mockGetExecution,
            agentActionRemoteRateLimiter: AgentActionRemoteRateLimiter(maxCallsPerMinute: 0),
            agentActionRemoteAuthorization: _agentActionRemoteAuthorization(
              featureFlags: mockFeatureFlags,
              getClientTokenPolicy: mockGetPolicy,
              authorizeSqlOperation: mockAuthorize,
            ),
            agentActionRemoteAuditStore: mockAudit,
          );

          final response = await dispatcherWithAudit.dispatch(
            const RpcRequest(
              jsonrpc: '2.0',
              method: AgentActionRpcConstants.agentActionRunRpcMethodName,
              id: 911,
              params: <String, dynamic>{
                'action_id': 'action-audit-auth-off',
                'idempotency_key': 'idem-audit-auth-off',
              },
            ),
            'agent-1',
            clientToken: 'tok-audit-auth-off',
          );

          check(response.error).isNull();
          verify(() => mockGetPolicy('tok-audit-auth-off')).called(1);
          final captured = verify(() => mockAudit.append(captureAny()));
          captured.called(2);
          final record = captured.captured.last as AgentActionRemoteAuditRecord;
          check(record.clientId).equals('audit-auth-off-client');
          check(record.tokenJti).equals('audit-auth-off-jti');
        },
      );
    });
  });
}

class MockOdbcNativeMetricsService extends Mock implements OdbcNativeMetricsService {}
