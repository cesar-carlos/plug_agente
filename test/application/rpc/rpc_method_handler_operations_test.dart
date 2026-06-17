import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler_operations.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart' show IIdempotencyStore, IdempotencyRecord;
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/rpc_method_dispatcher_test_support.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockIdempotencyStore extends Mock implements IIdempotencyStore {}

class MockRunAgentActionViaRemoteTrigger extends Mock implements RunAgentActionViaRemoteTrigger {}

DefaultRpcMethodHandlerOperations _buildOperations({
  required FeatureFlags featureFlags,
  IIdempotencyStore? idempotencyStore,
  RunAgentActionViaRemoteTrigger? runAgentActionViaRemoteTrigger,
}) {
  final gateway = MockDatabaseGateway();
  return DefaultRpcMethodHandlerOperations(
    streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
    databaseGateway: gateway,
    healthService: HealthService(
      metricsCollector: MetricsCollector(),
      gateway: gateway,
    ),
    normalizerService: MockQueryNormalizerService(),
    uuid: const Uuid(),
    authorizeSqlOperation: MockAuthorizeSqlOperation(),
    getClientTokenPolicy: MockGetClientTokenPolicy(),
    getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
    featureFlags: featureFlags,
    idempotencyStore: idempotencyStore,
    runAgentActionViaRemoteTrigger: runAgentActionViaRemoteTrigger,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      RpcResponse.success(id: 'fallback', result: const <String, dynamic>{}),
    );
    registerFallbackValue(
      const AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-1',
      ),
    );
  });

  group('DefaultRpcMethodHandlerOperations', () {
    late MockFeatureFlags featureFlags;

    setUp(() {
      featureFlags = MockFeatureFlags();
      when(() => featureFlags.enableSocketIdempotency).thenReturn(true);
      when(() => featureFlags.enableAgentActions).thenReturn(true);
      when(() => featureFlags.enableRemoteAgentActions).thenReturn(true);
      when(() => featureFlags.enableAgentActionsMaintenanceMode).thenReturn(false);
      when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(false);
      when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    });

    test('exposes sqlStreamingCoordinator after construction', () {
      final operations = _buildOperations(featureFlags: featureFlags);

      expect(operations.sqlStreamingCoordinator, isNotNull);
    });

    test('handleAgentActionRun delegates to agent action operations when runner is missing', () async {
      final operations = _buildOperations(featureFlags: featureFlags);

      final response = await operations.handleAgentActionRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 10,
          params: <String, dynamic>{'action_id': 'action-1'},
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error?.code, RpcErrorCode.internalError);
    });

    test('handleClientTokenGetPolicy rejects missing client token when authorization is enabled', () async {
      when(() => featureFlags.enableClientTokenAuthorization).thenReturn(true);
      when(() => featureFlags.enableClientTokenPolicyIntrospection).thenReturn(true);
      final operations = _buildOperations(featureFlags: featureFlags);

      final response = await operations.handleClientTokenGetPolicy(
        const RpcRequest(
          jsonrpc: '2.0',
          method: 'client_token.getPolicy',
          id: 11,
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error?.code, RpcErrorCode.authenticationFailed);
    });

    test('handleAgentGetHealth succeeds without client token', () async {
      final gateway = MockDatabaseGateway();
      final operations = DefaultRpcMethodHandlerOperations(
        streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
        databaseGateway: gateway,
        healthService: HealthService(
          metricsCollector: MetricsCollector(),
          gateway: gateway,
        ),
        normalizerService: MockQueryNormalizerService(),
        uuid: const Uuid(),
        authorizeSqlOperation: MockAuthorizeSqlOperation(),
        getClientTokenPolicy: MockGetClientTokenPolicy(),
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: featureFlags,
      );

      final response = await operations.handleAgentGetHealth(
        const RpcRequest(
          jsonrpc: '2.0',
          method: 'agent.get_health',
          id: 12,
        ),
        null,
      );

      expect(response.isSuccess, isTrue);
      expect(response.result, isA<Map<String, dynamic>>());
    });

    test('rejects agent.action idempotency fingerprint mismatch', () async {
      final idempotencyStore = MockIdempotencyStore();
      final remoteRunner = MockRunAgentActionViaRemoteTrigger();
      when(() => idempotencyStore.getRecord(any())).thenAnswer(
        (_) async => IdempotencyRecord(
          response: RpcResponse.success(id: 'cached', result: const <String, dynamic>{}),
          requestFingerprint: 'other-fingerprint',
        ),
      );

      final operations = _buildOperations(
        featureFlags: featureFlags,
        idempotencyStore: idempotencyStore,
        runAgentActionViaRemoteTrigger: remoteRunner,
      );

      final response = await operations.handleAgentActionRun(
        const RpcRequest(
          jsonrpc: '2.0',
          method: AgentActionRpcConstants.agentActionRunRpcMethodName,
          id: 13,
          params: <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-mismatch',
          },
        ),
        'agent-1',
        null,
      );

      expect(response.isSuccess, isFalse);
      expect(response.error?.code, RpcErrorCode.invalidParams);
      expect(
        (response.error?.data as Map<String, dynamic>?)?['reason'],
        AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason,
      );
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
  });
}
