import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockAuthorizationPolicyResolver extends Mock
    implements IAuthorizationPolicyResolver {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockQueryNormalizerService extends Mock
    implements QueryNormalizerService {}

class MockCompressionService extends Mock implements CompressionService {}

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
  late MockQueryNormalizerService mockNormalizer;
  late MockCompressionService mockCompression;
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
    mockNormalizer = MockQueryNormalizerService();
    mockCompression = MockCompressionService();
    authMetrics = AuthorizationMetricsCollector();

    when(() => mockFeatureFlags.enableClientTokenAuthorization)
        .thenReturn(true);

    final classifier = SqlOperationClassifier();
    final tokenValidation = ClientTokenValidationService(mockResolver);
    final authorizeSqlOperation = AuthorizeSqlOperation(
      classifier,
      tokenValidation,
    );

    dispatcher = RpcMethodDispatcher(
      databaseGateway: mockGateway,
      normalizerService: mockNormalizer,
      compressionService: mockCompression,
      uuid: const Uuid(),
      authorizeSqlOperation: authorizeSqlOperation,
      featureFlags: mockFeatureFlags,
      authMetrics: authMetrics,
    );
  });

  group('ClientTokenAuthorizationIntegration', () {
    test('should authorize when token policy allows SELECT on resource', () async {
      when(() => mockResolver.resolvePolicy('valid-token'))
          .thenAnswer((_) async => Success(policyAllowReadOnUsers()));

      final queryResponse = QueryResponse(
        id: 'resp-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [],
        timestamp: DateTime.now(),
      );
      when(() => mockGateway.executeQuery(any()))
          .thenAnswer((_) async => Success(queryResponse));
      when(() => mockNormalizer.normalize(any()))
          .thenAnswer((_) async => queryResponse);
      when(() => mockCompression.compress(any()))
          .thenAnswer((_) async => Success(queryResponse));

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
    });

    test('should deny when token policy does not allow resource', () async {
      when(() => mockResolver.resolvePolicy('valid-token'))
          .thenAnswer((_) async => Success(policyAllowReadOnUsers()));

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
      check(data['reason']).equals('missing_permission');
      check(authMetrics.getSummary().totalAuthorized).equals(0);
      check(authMetrics.getSummary().totalDenied).equals(1);
    });

    test('should deny when deny rule overrides allow', () async {
      when(() => mockResolver.resolvePolicy('valid-token'))
          .thenAnswer((_) async => Success(policyDenyAll()));

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
      check(data['reason']).equals('token_revoked');
    });

    test('should skip auth when feature flag is disabled', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization)
          .thenReturn(false);

      final queryResponse = QueryResponse(
        id: 'resp-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [],
        timestamp: DateTime.now(),
      );
      when(() => mockGateway.executeQuery(any()))
          .thenAnswer((_) async => Success(queryResponse));
      when(() => mockNormalizer.normalize(any()))
          .thenAnswer((_) async => queryResponse);
      when(() => mockCompression.compress(any()))
          .thenAnswer((_) async => Success(queryResponse));

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
  });
}
