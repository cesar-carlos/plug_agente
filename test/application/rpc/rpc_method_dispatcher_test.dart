import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock
    implements QueryNormalizerService {}

class MockCompressionService extends Mock implements CompressionService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockIdempotencyStore extends Mock implements IIdempotencyStore {}

class MockStreamingDatabaseGateway extends Mock
    implements IStreamingDatabaseGateway {}

class MockAgentConfigRepository extends Mock
    implements IAgentConfigRepository {}

class MockRpcStreamEmitter extends Mock implements IRpcStreamEmitter {}

Map<String, dynamic> _userAt(int i) => {'id': i, 'name': 'user$i'};

void main() {
  group('RpcMethodDispatcher', () {
    late MockDatabaseGateway mockGateway;
    late MockQueryNormalizerService mockNormalizer;
    late MockCompressionService mockCompression;
    late MockStreamingDatabaseGateway mockStreamingGateway;
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
      registerFallbackValue(
        RpcResponse.success(id: 'test', result: <String, dynamic>{}),
      );
      registerFallbackValue(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: [],
        ),
      );
      registerFallbackValue(
        const RpcStreamComplete(
          streamId: 's-1',
          requestId: 'req-1',
          totalRows: 0,
        ),
      );
      registerFallbackValue(Duration.zero);
      registerFallbackValue('');
    });

    late MockAuthorizeSqlOperation mockAuthorize;
    late MockFeatureFlags mockFeatureFlags;

    setUp(() {
      mockGateway = MockDatabaseGateway();
      mockNormalizer = MockQueryNormalizerService();
      mockCompression = MockCompressionService();
      mockStreamingGateway = MockStreamingDatabaseGateway();
      mockAuthorize = MockAuthorizeSqlOperation();
      mockFeatureFlags = MockFeatureFlags();
      when(
        () => mockFeatureFlags.enableClientTokenAuthorization,
      ).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketStreamingChunks,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketStreamingFromDb,
      ).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketCancelMethod).thenReturn(false);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        normalizerService: mockNormalizer,
        compressionService: mockCompression,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        featureFlags: mockFeatureFlags,
        streamingGateway: mockStreamingGateway,
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

    test(
      'should stream from DB when enableSocketStreamingFromDb and SELECT without params',
      () async {
        when(
          () => mockFeatureFlags.enableSocketStreamingChunks,
        ).thenReturn(true);
        when(
          () => mockFeatureFlags.enableSocketStreamingFromDb,
        ).thenReturn(true);

        final mockConfigRepo = MockAgentConfigRepository();
        final config = Config(
          id: 'cfg-1',
          driverName: 'SQL Server',
          odbcDriverName: 'ODBC Driver 17',
          connectionString: 'DSN=Test',
          username: 'u',
          databaseName: 'db',
          host: 'localhost',
          port: 1433,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        when(
          mockConfigRepo.getCurrentConfig,
        ).thenAnswer((_) async => Success(config));

        when(
          () => mockStreamingGateway.executeQueryStream(
            any(),
            any(),
            any(),
            fetchSize: any(named: 'fetchSize'),
            chunkSizeBytes: any(named: 'chunkSizeBytes'),
          ),
        ).thenAnswer((invocation) async {
          final onChunk =
              invocation.positionalArguments[2]
                  as void Function(List<Map<String, dynamic>>);
          onChunk([
            {'id': 1, 'name': 'a'},
            {'id': 2, 'name': 'b'},
          ]);
          onChunk([
            {'id': 3, 'name': 'c'},
          ]);
          return const Success(unit);
        });

        dispatcher = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          normalizerService: mockNormalizer,
          compressionService: mockCompression,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          featureFlags: mockFeatureFlags,
          configRepository: mockConfigRepo,
          streamingGateway: mockStreamingGateway,
        );

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {'sql': 'SELECT * FROM users'},
        );

        final mockEmitter = MockRpcStreamEmitter();
        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          streamEmitter: mockEmitter,
        );

        expect(response.isSuccess, isTrue);
        final result = response.result as Map<String, dynamic>;
        expect(result['stream_id'], isNotNull);
        expect(result['rows'], isEmpty);
        expect(result['row_count'], equals(0));

        verify(() => mockEmitter.emitChunk(any())).called(2);
        verify(() => mockEmitter.emitComplete(any())).called(1);
        verifyNever(() => mockGateway.executeQuery(any()));
      },
    );

    test(
      'should emit chunks when streaming enabled and result is large',
      () async {
        when(
          () => mockFeatureFlags.enableSocketStreamingChunks,
        ).thenReturn(true);

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {'sql': 'SELECT * FROM large_table'},
        );

        final largeData = List.generate(600, _userAt);
        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: largeData,
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

        final mockEmitter = MockRpcStreamEmitter();
        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          streamEmitter: mockEmitter,
        );

        expect(response.isSuccess, isTrue);
        final result = response.result as Map<String, dynamic>;
        expect(result['stream_id'], isNotNull);
        expect(result['rows'], isEmpty);
        expect(result['row_count'], equals(0));

        verify(() => mockEmitter.emitChunk(any())).called(greaterThan(1));
        verify(() => mockEmitter.emitComplete(any())).called(1);
      },
    );

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

    test(
      'should return unauthorized when auth enabled and token denies',
      () async {
        when(
          () => mockFeatureFlags.enableClientTokenAuthorization,
        ).thenReturn(true);
        when(
          () => mockAuthorize(
            token: any(named: 'token'),
            sql: any(named: 'sql'),
          ),
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
      },
    );

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

    test(
      'should return cached response when idempotency key repeats',
      () async {
        final mockStore = MockIdempotencyStore();
        when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

        dispatcher = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          normalizerService: mockNormalizer,
          compressionService: mockCompression,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          featureFlags: mockFeatureFlags,
          idempotencyStore: mockStore,
          streamingGateway: mockStreamingGateway,
        );

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: <String, dynamic>{
            'sql': 'SELECT 1',
            'idempotency_key': 'key-abc',
          },
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [
            {'x': 1},
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

        when(() => mockStore.get(any())).thenReturn(null);

        final first = await dispatcher.dispatch(request, 'agent-1');

        expect(first.isSuccess, isTrue);

        when(() => mockStore.get(any())).thenReturn(first);

        final second = await dispatcher.dispatch(request, 'agent-1');

        expect(second.isSuccess, isTrue);
        expect(second.result, equals(first.result));
      },
    );

    group('sql.cancel', () {
      test('should return methodNotFound when flag is disabled', () async {
        when(() => mockFeatureFlags.enableSocketCancelMethod).thenReturn(false);

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.cancel',
          id: 'req-cancel',
          params: {'request_id': 'req-1'},
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isError, isTrue);
        expect(response.error!.code, equals(RpcErrorCode.methodNotFound));
        verifyNever(() => mockStreamingGateway.hasActiveStream);
      });

      test('should return executionNotFound when no active stream', () async {
        when(() => mockFeatureFlags.enableSocketCancelMethod).thenReturn(true);
        when(() => mockStreamingGateway.hasActiveStream).thenReturn(false);

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.cancel',
          id: 'req-cancel',
          params: {'request_id': 'req-1'},
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isError, isTrue);
        expect(response.error!.code, equals(RpcErrorCode.executionNotFound));
        final data = response.error!.data as Map<String, dynamic>;
        expect(data['reason'], equals('execution_not_found'));
      });

      test(
        'should return invalidParams when neither execution_id nor request_id',
        () async {
          when(
            () => mockFeatureFlags.enableSocketCancelMethod,
          ).thenReturn(true);

          const request = RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.cancel',
            id: 'req-cancel',
            params: <String, dynamic>{},
          );

          final response = await dispatcher.dispatch(request, 'agent-1');

          expect(response.isError, isTrue);
          expect(response.error!.code, equals(RpcErrorCode.invalidParams));
        },
      );

      test(
        'should cancel and return success when active stream exists',
        () async {
          when(
            () => mockFeatureFlags.enableSocketCancelMethod,
          ).thenReturn(true);
          when(() => mockStreamingGateway.hasActiveStream).thenReturn(true);
          when(
            () => mockStreamingGateway.cancelActiveStream(),
          ).thenAnswer((_) async => const Success(unit));

          const request = RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.cancel',
            id: 'req-cancel',
            params: {
              'execution_id': 'exec-1',
              'request_id': 'req-1',
            },
          );

          final response = await dispatcher.dispatch(request, 'agent-1');

          expect(response.isSuccess, isTrue);
          final result = response.result as Map<String, dynamic>;
          expect(result['cancelled'], isTrue);
          expect(result['execution_id'], equals('exec-1'));
          expect(result['request_id'], equals('req-1'));
          verify(() => mockStreamingGateway.cancelActiveStream()).called(1);
        },
      );
    });
  });
}
