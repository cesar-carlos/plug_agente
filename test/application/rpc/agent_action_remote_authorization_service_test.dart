import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RpcRequest(
        jsonrpc: '2.0',
        method: AgentActionRpcConstants.agentActionRunRpcMethodName,
        id: 1,
        params: <String, dynamic>{},
      ),
    );
  });

  group('AgentActionRemoteAuthorizationService', () {
    late MockFeatureFlags mockFeatureFlags;
    late MockGetClientTokenPolicy mockGetPolicy;
    late MockAuthorizeSqlOperation mockAuthorize;
    late AgentActionRemoteAuthorizationService service;

    setUp(() {
      mockFeatureFlags = MockFeatureFlags();
      mockGetPolicy = MockGetClientTokenPolicy();
      mockAuthorize = MockAuthorizeSqlOperation();

      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(true);

      when(
        () => mockAuthorize(
          token: any(named: 'token'),
          sql: any(named: 'sql'),
          requestDatabase: any(named: 'requestDatabase'),
          requestId: any(named: 'requestId'),
          method: any(named: 'method'),
        ),
      ).thenAnswer((_) async => const Success(unit));

      service = AgentActionRemoteAuthorizationService(
        featureFlags: mockFeatureFlags,
        getClientTokenPolicy: mockGetPolicy,
        authorizeSqlOperation: mockAuthorize,
      );
    });

    test('should deny when client token is missing and authorization is required', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: AgentActionRpcConstants.agentActionRunRpcMethodName,
        id: 9,
        params: <String, dynamic>{'action_id': 'action-1'},
      );
      final result = await service.authorizeIfNeeded(
        request: request,
        clientToken: null,
        authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionRun,
        requiredAgentActionScope: AgentActionRpcConstants.agentActionsRunScope,
        actionIdForAllowlist: 'action-1',
      );

      check(result.denied).isNotNull();
      check(result.denied!.error!.code).equals(RpcErrorCode.authenticationFailed);
      final data = result.denied!.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(RpcClientTokenConstants.missingClientTokenReason);
      verifyNever(() => mockGetPolicy(any()));
    });

    test('should deny when policy scopes exclude required run scope', () async {
      var permissionDenied = 0;
      service = AgentActionRemoteAuthorizationService(
        featureFlags: mockFeatureFlags,
        getClientTokenPolicy: mockGetPolicy,
        authorizeSqlOperation: mockAuthorize,
        onPermissionDenied: () => permissionDenied++,
      );
      when(() => mockGetPolicy(any())).thenAnswer(
        (_) async => const Success(
          ClientTokenPolicy(
            clientId: 'client-1',
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

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: AgentActionRpcConstants.agentActionRunRpcMethodName,
        id: 10,
        params: <String, dynamic>{'action_id': 'action-1'},
      );
      final result = await service.authorizeIfNeeded(
        request: request,
        clientToken: 'tok',
        authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionRun,
        requiredAgentActionScope: AgentActionRpcConstants.agentActionsRunScope,
        actionIdForAllowlist: 'action-1',
      );

      check(result.denied).isNotNull();
      check(result.denied!.error!.code).equals(RpcErrorCode.unauthorized);
      final data = result.denied!.error!.data as Map<String, dynamic>;
      check(data['reason']).equals(AgentActionRpcConstants.agentActionPermissionDeniedErrorReason);
      check(data['required_scope']).equals(AgentActionRpcConstants.agentActionsRunScope);
      check(data['action_id']).equals('action-1');
      check(permissionDenied).equals(1);
      verifyNever(
        () => mockAuthorize(
          token: any(named: 'token'),
          sql: any(named: 'sql'),
          requestDatabase: any(named: 'requestDatabase'),
          requestId: any(named: 'requestId'),
          method: any(named: 'method'),
        ),
      );
    });

    test('should resolve policy for audit when token auth is on but authorization did not run', () async {
      when(() => mockGetPolicy('tok-audit-auth-on')).thenAnswer(
        (_) async => const Success(
          ClientTokenPolicy(
            clientId: 'audit-auth-on-client',
            tokenId: 'audit-auth-on-jti',
            allTables: false,
            allViews: false,
            rules: [],
          ),
        ),
      );

      final policy = await service.resolvePolicyForAudit(
        clientToken: 'tok-audit-auth-on',
      );

      check(policy?.clientId).equals('audit-auth-on-client');
      check(AgentActionRemoteAuthorizationService.auditTokenJti(policy)).equals('audit-auth-on-jti');
      verify(() => mockGetPolicy('tok-audit-auth-on')).called(1);
    });

    test('should resolve policy for audit when token auth is off', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);
      when(() => mockGetPolicy('tok-audit')).thenAnswer(
        (_) async => const Success(
          ClientTokenPolicy(
            clientId: 'audit-only-client',
            tokenId: 'audit-only-jti',
            allTables: false,
            allViews: false,
            rules: [],
          ),
        ),
      );

      final policy = await service.resolvePolicyForAudit(
        clientToken: 'tok-audit',
      );

      check(policy?.clientId).equals('audit-only-client');
      check(AgentActionRemoteAuthorizationService.auditTokenJti(policy)).equals('audit-only-jti');
    });
  });
}
