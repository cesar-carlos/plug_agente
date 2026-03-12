import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock
    implements QueryNormalizerService {}

class MockCompressionService extends Mock implements CompressionService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  group('RpcMethodDispatcher', () {
    late MockDatabaseGateway mockGateway;
    late MockQueryNormalizerService mockNormalizer;
    late MockCompressionService mockCompression;
    late RpcMethodDispatcher dispatcher;

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

    late MockAuthorizeSqlOperation mockAuthorize;
    late MockFeatureFlags mockFeatureFlags;

    setUp(() {
      mockGateway = MockDatabaseGateway();
      mockNormalizer = MockQueryNormalizerService();
      mockCompression = MockCompressionService();
      mockAuthorize = MockAuthorizeSqlOperation();
      mockFeatureFlags = MockFeatureFlags();
      when(() => mockFeatureFlags.enableClientTokenAuthorization)
          .thenReturn(false);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        normalizerService: mockNormalizer,
        compressionService: mockCompression,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        featureFlags: mockFeatureFlags,
      );
    });

    test('should return methodNotFound for unknown method', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'unknown.method',
        id: 'req-1',
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.methodNotFound));
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['reason'], equals('method_not_found'));
      expect(data['category'], equals('validation'));
      expect(data['correlation_id'], equals('req-1'));
    });

    test('should return invalidParams when sql is missing', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: <String, dynamic>{},
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.invalidParams));
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['reason'], equals('invalid_params'));
      expect(data['category'], equals('validation'));
      expect(data['technical_message'], equals('sql is required'));
    });

    test('should return invalidParams when params is not an object', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: ['invalid'],
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.invalidParams));
    });

    test('should execute sql.execute successfully', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'SELECT * FROM users',
        },
      );

      final queryResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: [
          {'id': 1, 'name': 'John'},
        ],
        timestamp: DateTime.now(),
      );

      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse));
      when(
        () => mockNormalizer.normalize(any()),
      ).thenAnswer((_) async => queryResponse);
      when(
        () => mockCompression.compress(any()),
      ).thenAnswer((_) async => Success(queryResponse));

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      expect(response.result, isNotNull);
      final result = response.result as Map<String, dynamic>;
      expect(result['rows'], isNotNull);
      expect(result['row_count'], equals(1));
    });

    test('should return error when SQL validation fails', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'DROP TABLE users',
        },
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.invalidParams));
    });

    test('should execute sql.executeBatch successfully', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.executeBatch',
        id: 'req-1',
        params: {
          'commands': [
            {'sql': 'SELECT * FROM users WHERE id = 1'},
            {'sql': 'SELECT COUNT(*) FROM users'},
          ],
        },
      );

      final queryResponse1 = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: [
          {'id': 1, 'name': 'John'},
        ],
        timestamp: DateTime.now(),
      );

      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse1));
      when(() => mockNormalizer.normalize(any())).thenAnswer(
        (invocation) async =>
            invocation.positionalArguments[0] as QueryResponse,
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      final result = response.result as Map<String, dynamic>;
      expect(result['items'], hasLength(2));
      expect(result['total_commands'], equals(2));
    });

    test('should return invalidParams when batch commands is empty', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.executeBatch',
        id: 'req-1',
        params: {
          'commands': <dynamic>[],
        },
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.invalidParams));
    });

    test('should return unauthorized when auth enabled and token denies', () async {
      when(() => mockFeatureFlags.enableClientTokenAuthorization)
          .thenReturn(true);
      when(
        () => mockAuthorize(token: any(named: 'token'), sql: any(named: 'sql')),
      ).thenAnswer(
        (_) async => Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Authorization denied for delete on dbo.users',
            context: {
              'authorization': true,
              'reason': 'missing_permission',
              'client_id': 'client-acme',
              'operation': 'delete',
              'resource': 'dbo.users',
              'user_message': 'Seu cliente nao possui permissao.',
            },
          ),
        ),
      );

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'DELETE FROM dbo.users WHERE id = 1',
          'client_token': 'bearer-xyz',
        },
      );

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        clientToken: 'bearer-xyz',
      );

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.unauthorized));
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['reason'], equals('missing_permission'));
      expect(data['category'], equals('auth'));
      expect(data['client_id'], equals('client-acme'));
      verifyNever(() => mockGateway.executeQuery(any()));
    });

    test('should include instance in error data', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'SELECT * FROM users',
        },
      );

      when(() => mockGateway.executeQuery(any())).thenAnswer(
        (_) async => Failure(domain.QueryExecutionFailure('Query failed')),
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isError, isTrue);
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['instance'], equals('req-1'));
    });
  });
}
