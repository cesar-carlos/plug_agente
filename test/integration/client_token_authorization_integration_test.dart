import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

HealthService _healthServiceForIntegration(IDatabaseGateway gateway) => HealthService(
      metricsCollector: MetricsCollector(),
      gateway: gateway,
    );

class MockAuthorizationPolicyResolver extends Mock implements IAuthorizationPolicyResolver {}

class MockClientTokenLocalDataSource extends Mock implements ClientTokenLocalDataSource {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

final ClientTokenGetPolicyRateLimiter _integrationNoopGetPolicyRateLimiter = ClientTokenGetPolicyRateLimiter(
  maxCallsPerMinute: 0,
);

class MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      QueryRequest(
        id: 'test',
        agentId: 'test',
        query: 'SELECT * FROM test',
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
  });

  late RpcMethodDispatcher dispatcher;
  late MockDatabaseGateway mockGateway;
  late MockAuthorizationPolicyResolver mockResolver;
  late MockFeatureFlags mockFeatureFlags;
  late MockClientTokenLocalDataSource mockLocalDataSource;
  late MockQueryNormalizerService mockNormalizer;
  late AuthorizationMetricsCollector authMetrics;

  ClientTokenPolicy policyAllowReadOnUsers() {
    return const ClientTokenPolicy(
      clientId: 'test-client',
      allTables: false,
      allViews: false,
      allPermissions: false,
      rules: [
        ClientTokenRule(
          resource: DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'dbo.users',
          ),
          permissions: ClientPermissionSet(
            canRead: true,
            canUpdate: false,
            canDelete: false,
          ),
          effect: ClientTokenRuleEffect.allow,
        ),
      ],
    );
  }

  ClientTokenPolicy policyDenyAll() {
    return const ClientTokenPolicy(
      clientId: 'test-client',
      allTables: true,
      allViews: true,
      allPermissions: true,
      rules: [
        ClientTokenRule(
          resource: DatabaseResource(
            resourceType: DatabaseResourceType.table,
            name: 'dbo.users',
          ),
          permissions: ClientPermissionSet(
            canRead: true,
            canUpdate: true,
            canDelete: true,
          ),
          effect: ClientTokenRuleEffect.deny,
        ),
      ],
    );
  }

  setUp(() {
    mockGateway = MockDatabaseGateway();
    mockResolver = MockAuthorizationPolicyResolver();
    mockFeatureFlags = MockFeatureFlags();
    mockLocalDataSource = MockClientTokenLocalDataSource();
    mockNormalizer = MockQueryNormalizerService();
    authMetrics = AuthorizationMetricsCollector();

    when(
      () => mockFeatureFlags.enableClientTokenAuthorization,
    ).thenReturn(true);
    when(
      () => mockFeatureFlags.enableClientTokenPolicyIntrospection,
    ).thenReturn(true);
    when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(false);
    when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => mockFeatureFlags.enableSocketCancelMethod).thenReturn(false);
    when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(false);
    when(() => mockFeatureFlags.enableSocketJwksValidation).thenReturn(false);
    when(
      () => mockFeatureFlags.enableSocketRevokedTokenInSession,
    ).thenReturn(false);
    when(() => mockFeatureFlags.enableSocketStreamingFromDb).thenReturn(false);
    when(() => mockFeatureFlags.enableSocketStreamingChunks).thenReturn(false);

    final classifier = SqlOperationClassifier();
    final tokenValidation = ClientTokenValidationService(mockResolver);
    final authorizeSqlOperation = AuthorizeSqlOperation(
      classifier,
      tokenValidation,
    );
    final getClientTokenPolicy = GetClientTokenPolicy(mockResolver);

    dispatcher = RpcMethodDispatcher(
      databaseGateway: mockGateway,
      healthService: _healthServiceForIntegration(mockGateway),
      normalizerService: mockNormalizer,
      uuid: const Uuid(),
      authorizeSqlOperation: authorizeSqlOperation,
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: _integrationNoopGetPolicyRateLimiter,
      featureFlags: mockFeatureFlags,
      authMetrics: authMetrics,
    );
  });

  group('ClientTokenAuthorizationIntegration', () {
    test(
      'should authorize when token policy allows SELECT on resource',
      () async {
        when(
          () => mockResolver.resolvePolicy('valid-token'),
        ).thenAnswer((_) async => Success(policyAllowReadOnUsers()));

        final queryResponse = QueryResponse(
          id: 'resp-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [],
          timestamp: DateTime.now(),
        );
        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(
          () => mockNormalizer.normalize(any()),
        ).thenAnswer((_) => queryResponse);

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {'sql': 'SELECT * FROM dbo.users'},
        );

        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          clientToken: 'valid-token',
        );

        check(response.isError).isFalse();
        check(authMetrics.getSummary().totalAuthorized).equals(1);
        check(authMetrics.getSummary().totalDenied).equals(0);
      },
    );

    test('should deny when token policy does not allow resource', () async {
      when(
        () => mockResolver.resolvePolicy('valid-token'),
      ).thenAnswer((_) async => Success(policyAllowReadOnUsers()));

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {'sql': 'SELECT * FROM dbo.other_table'},
      );

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        clientToken: 'valid-token',
      );

      check(response.isError).isTrue();
      check(response.error?.code).equals(RpcErrorCode.unauthorized);
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals('unauthorized');
      check(data['odbc_reason']).equals('missing_permission');
      final denied = data['denied_resources'] as List<dynamic>?;
      check(denied).isNotNull();
      check(denied!.length).equals(1);
      check(denied[0] as String).equals('dbo.other_table');
      check(data['resource']).equals('dbo.other_table');
      check(authMetrics.getSummary().totalAuthorized).equals(0);
      check(authMetrics.getSummary().totalDenied).equals(1);
    });

    test('should deny when deny rule overrides allow', () async {
      when(
        () => mockResolver.resolvePolicy('valid-token'),
      ).thenAnswer((_) async => Success(policyDenyAll()));

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {'sql': 'SELECT * FROM dbo.users'},
      );

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        clientToken: 'valid-token',
      );

      check(response.isError).isTrue();
      check(authMetrics.getSummary().totalDenied).equals(1);
    });

    test('should deny when token is invalid or revoked', () async {
      when(() => mockResolver.resolvePolicy('revoked-token')).thenAnswer(
        (_) async => const Success(
          ClientTokenPolicy(
            clientId: 'test-client',
            allTables: false,
            allViews: false,
            allPermissions: false,
            rules: [],
            isRevoked: true,
          ),
        ),
      );

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {'sql': 'SELECT * FROM dbo.users'},
      );

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        clientToken: 'revoked-token',
      );

      check(response.isError).isTrue();
      final data = response.error!.data as Map<String, dynamic>;
      check(data['reason']).equals('unauthorized');
      check(data['odbc_reason']).equals('token_revoked');
      final dr = data['denied_resources'] as List<dynamic>?;
      check(dr).isNotNull();
      check(dr!.length).equals(1);
      check(dr[0] as String).equals('dbo.users');
    });

    test('should skip auth when feature flag is disabled', () async {
      when(
        () => mockFeatureFlags.enableClientTokenAuthorization,
      ).thenReturn(false);

      final queryResponse = QueryResponse(
        id: 'resp-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [],
        timestamp: DateTime.now(),
      );
      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse));
      when(
        () => mockNormalizer.normalize(any()),
      ).thenAnswer((_) => queryResponse);

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {'sql': 'SELECT * FROM dbo.users'},
      );

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        clientToken: 'any-token',
      );

      check(response.isError).isFalse();
      verifyNever(() => mockResolver.resolvePolicy(any()));
    });

    test(
      'should deny rpc request when token jti is not found in local store',
      () async {
        const tokenId = 'missing-local-token';
        const tokenHash = 'hash-missing-local-token';
        when(
          () => mockLocalDataSource.hashTokenForLookup(any()),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => null);

        final resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
        );
        final authorizeSqlOperation = AuthorizeSqlOperation(
          SqlOperationClassifier(),
          ClientTokenValidationService(resolver),
        );
        final getClientTokenPolicy = GetClientTokenPolicy(resolver);
        final dispatcherWithLocalResolver = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthServiceForIntegration(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: authorizeSqlOperation,
          getClientTokenPolicy: getClientTokenPolicy,
          getPolicyRateLimiter: _integrationNoopGetPolicyRateLimiter,
          featureFlags: mockFeatureFlags,
          authMetrics: authMetrics,
        );

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-local-1',
          params: {'sql': 'SELECT * FROM dbo.users'},
        );

        final response = await dispatcherWithLocalResolver.dispatch(
          request,
          'agent-1',
          clientToken: _buildTokenWithJti(
            tokenId: tokenId,
            payloadPolicy: const {
              'client_id': 'payload-client',
              'all_tables': true,
              'all_views': true,
              'all_permissions': true,
              'rules': <Map<String, dynamic>>[],
            },
          ),
        );

        check(response.isError).isTrue();
        check(response.error?.code).equals(RpcErrorCode.unauthorized);
        final data = response.error!.data as Map<String, dynamic>;
        check(data['reason']).equals('unauthorized');
        check(data['odbc_reason']).equals('token_not_found');
        verify(() => mockLocalDataSource.hashTokenForLookup(any())).called(1);
        verify(() => mockLocalDataSource.getTokenByHash(tokenHash)).called(1);
        verifyNever(() => mockGateway.executeQuery(any()));
      },
    );

    test(
      'should authorize rpc request using local policy over token payload',
      () async {
        const tokenId = 'local-token-allow';
        const tokenHash = 'hash-local-token-allow';
        final localSummary = ClientTokenSummary(
          id: tokenId,
          clientId: 'local-client',
          createdAt: DateTime.now().toUtc(),
          isRevoked: false,
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: const [
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.table,
                name: 'dbo.users',
              ),
              permissions: ClientPermissionSet(
                canRead: true,
                canUpdate: false,
                canDelete: false,
              ),
              effect: ClientTokenRuleEffect.allow,
            ),
          ],
        );
        when(
          () => mockLocalDataSource.hashTokenForLookup(any()),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => localSummary);

        final resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
        );
        final authorizeSqlOperation = AuthorizeSqlOperation(
          SqlOperationClassifier(),
          ClientTokenValidationService(resolver),
        );
        final getClientTokenPolicy = GetClientTokenPolicy(resolver);
        final dispatcherWithLocalResolver = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthServiceForIntegration(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: authorizeSqlOperation,
          getClientTokenPolicy: getClientTokenPolicy,
          getPolicyRateLimiter: _integrationNoopGetPolicyRateLimiter,
          featureFlags: mockFeatureFlags,
          authMetrics: authMetrics,
        );

        final queryResponse = QueryResponse(
          id: 'resp-local-1',
          requestId: 'req-local-2',
          agentId: 'agent-1',
          data: const [],
          timestamp: DateTime.now(),
        );
        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(
          () => mockNormalizer.normalize(any()),
        ).thenAnswer((_) => queryResponse);

        final response = await dispatcherWithLocalResolver.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.execute',
            id: 'req-local-2',
            params: {'sql': 'SELECT * FROM dbo.users'},
          ),
          'agent-1',
          clientToken: _buildTokenWithJti(
            tokenId: tokenId,
            payloadPolicy: const {
              'client_id': 'payload-client',
              'all_tables': false,
              'all_views': false,
              'all_permissions': false,
              'rules': <Map<String, dynamic>>[],
            },
          ),
        );

        check(response.isError).isFalse();
        verify(() => mockLocalDataSource.hashTokenForLookup(any())).called(1);
        verify(() => mockLocalDataSource.getTokenByHash(tokenHash)).called(1);
        verify(() => mockGateway.executeQuery(any())).called(1);
      },
    );

    test(
      'should return token_id and issued_at on client_token.getPolicy via local resolver',
      () async {
        const tokenId = 'policy-introspect-1';
        const tokenHash = 'hash-policy-introspect-1';
        final localSummary = ClientTokenSummary(
          id: tokenId,
          clientId: 'local-client',
          createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: false,
          rules: const [],
        );
        when(
          () => mockLocalDataSource.hashTokenForLookup(any()),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => localSummary);

        final resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
        );
        final authorizeSqlOperation = AuthorizeSqlOperation(
          SqlOperationClassifier(),
          ClientTokenValidationService(resolver),
        );
        final getClientTokenPolicy = GetClientTokenPolicy(resolver);
        final dispatcherWithLocalResolver = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          healthService: _healthServiceForIntegration(mockGateway),
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: authorizeSqlOperation,
          getClientTokenPolicy: getClientTokenPolicy,
          getPolicyRateLimiter: _integrationNoopGetPolicyRateLimiter,
          featureFlags: mockFeatureFlags,
          authMetrics: authMetrics,
        );

        final response = await dispatcherWithLocalResolver.dispatch(
          const RpcRequest(
            jsonrpc: '2.0',
            method: 'client_token.getPolicy',
            id: 'req-get-policy',
            params: {'client_token': 'opaque'},
          ),
          'agent-1',
          clientToken: 'opaque',
        );

        check(response.isError).isFalse();
        final result = response.result as Map<String, dynamic>;
        check(result['token_id']).equals(tokenId);
        check(result['issued_at']).equals('2024-01-02T03:04:05.000Z');
      },
    );
  });
}

String _buildTokenWithJti({
  required String tokenId,
  required Map<String, dynamic> payloadPolicy,
}) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode(
        {
          'jti': tokenId,
          'policy': payloadPolicy,
        },
      ),
    ),
  );
  return '$header.$payload.signature';
}
