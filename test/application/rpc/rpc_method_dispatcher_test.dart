import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock
    implements QueryNormalizerService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockIdempotencyStore extends Mock implements IIdempotencyStore {}

class MockStreamingDatabaseGateway extends Mock
    implements IStreamingDatabaseGateway {}

class MockAgentConfigRepository extends Mock
    implements IAgentConfigRepository {}

class MockRpcStreamEmitter extends Mock implements IRpcStreamEmitter {}

MockRpcStreamEmitter _stubRpcStreamEmitter() {
  final emitter = MockRpcStreamEmitter();
  when(() => emitter.emitChunk(any())).thenAnswer((_) async => true);
  when(() => emitter.emitComplete(any())).thenAnswer((_) async {});
  return emitter;
}

Map<String, dynamic> _userAt(int i) => {'id': i, 'name': 'user$i'};

void main() {
  setUpAll(() {
    registerFallbackValue(StreamingCancelReason.user);
  });

  group('RpcMethodDispatcher', () {
    late MockDatabaseGateway mockGateway;
    late MockQueryNormalizerService mockNormalizer;
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
      registerFallbackValue(const Duration(seconds: 7));
      registerFallbackValue('');
      registerFallbackValue(
        const SqlCommand(
          sql: 'SELECT 1',
        ),
      );
      registerFallbackValue(const SqlExecutionOptions());
    });

    late MockAuthorizeSqlOperation mockAuthorize;
    late MockFeatureFlags mockFeatureFlags;

    setUp(() {
      mockGateway = MockDatabaseGateway();
      mockNormalizer = MockQueryNormalizerService();
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
      ).thenAnswer((_) => queryResponse);

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      expect(response.result, isNotNull);
      final result = response.result as Map<String, dynamic>;
      expect(result['sql_handling_mode'], 'managed');
      expect(result['max_rows_handling'], 'response_truncation');
      expect(result['rows'], isNotNull);
      expect(result['row_count'], equals(1));
    });

    test('should return multi-result payload for sql.execute', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'SELECT 1; SELECT 2;',
          'options': {'multi_result': true},
        },
      );

      final queryResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'first_value': 1},
        ],
        timestamp: DateTime.now(),
        columnMetadata: const [
          {'name': 'first_value'},
        ],
        resultSets: const [
          QueryResultSet(
            index: 0,
            rows: [
              {'first_value': 1},
            ],
            rowCount: 1,
            columnMetadata: [
              {'name': 'first_value'},
            ],
          ),
          QueryResultSet(
            index: 1,
            rows: [
              {'second_value': 2},
            ],
            rowCount: 1,
            columnMetadata: [
              {'name': 'second_value'},
            ],
          ),
        ],
        items: const [
          QueryResponseItem.resultSet(
            index: 0,
            resultSet: QueryResultSet(
              index: 0,
              rows: [
                {'first_value': 1},
              ],
              rowCount: 1,
              columnMetadata: [
                {'name': 'first_value'},
              ],
            ),
          ),
          QueryResponseItem.rowCount(
            index: 1,
            rowCount: 3,
          ),
          QueryResponseItem.resultSet(
            index: 2,
            resultSet: QueryResultSet(
              index: 1,
              rows: [
                {'second_value': 2},
              ],
              rowCount: 1,
              columnMetadata: [
                {'name': 'second_value'},
              ],
            ),
          ),
        ],
      );

      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse));
      when(
        () => mockNormalizer.normalize(any()),
      ).thenAnswer((_) => queryResponse);

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      final result = response.result as Map<String, dynamic>;
      expect(result['sql_handling_mode'], 'managed');
      expect(result['multi_result'], isTrue);
      expect(result['result_set_count'], 2);
      expect(result['item_count'], 3);
      expect(result['result_sets'] as List<dynamic>, hasLength(2));
      expect(result['items'] as List<dynamic>, hasLength(3));
    });

    test(
      'should include multi_result envelope keys when result sets are empty',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT 1 WHERE 1=0; SELECT 2 WHERE 1=0;',
            'options': {'multi_result': true},
          },
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const <Map<String, dynamic>>[],
          timestamp: DateTime.now(),
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(
          () => mockNormalizer.normalize(any()),
        ).thenAnswer((_) => queryResponse);

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isSuccess, isTrue);
        final result = response.result as Map<String, dynamic>;
        expect(result['multi_result'], isTrue);
        expect(result['result_set_count'], 0);
        expect(result['item_count'], 0);
        expect(result['result_sets'], isA<List<dynamic>>());
        expect(result['items'], isA<List<dynamic>>());
        expect(result['result_sets'] as List<dynamic>, isEmpty);
        expect(result['items'] as List<dynamic>, isEmpty);
      },
    );

    test(
      'should truncate each result_set when multi_result respects max_rows',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT 1; SELECT 2;',
            'options': {'multi_result': true, 'max_rows': 1},
          },
        );

        const rs0 = QueryResultSet(
          index: 0,
          rows: [
            {'a': 0},
            {'a': 1},
            {'a': 2},
          ],
          rowCount: 3,
        );
        const rs1 = QueryResultSet(
          index: 1,
          rows: [
            {'b': 0},
            {'b': 1},
          ],
          rowCount: 2,
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: rs0.rows,
          timestamp: DateTime.now(),
          resultSets: [rs0, rs1],
          items: const [
            QueryResponseItem.resultSet(index: 0, resultSet: rs0),
            QueryResponseItem.resultSet(index: 1, resultSet: rs1),
          ],
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(() => mockNormalizer.normalize(any())).thenAnswer(
          (invocation) =>
              invocation.positionalArguments[0] as QueryResponse,
        );

        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          limits: const TransportLimits(),
        );

        expect(response.isSuccess, isTrue);
        final result = response.result as Map<String, dynamic>;
        final sets = result['result_sets'] as List<dynamic>;
        expect((sets[0] as Map<String, dynamic>)['rows'], hasLength(1));
        expect((sets[1] as Map<String, dynamic>)['rows'], hasLength(1));
        expect(result['truncated'], isTrue);
      },
    );

    test(
      'should reject multi_result execution when named parameters are used',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT * FROM users WHERE id = :id; SELECT 2;',
            'params': {'id': 1},
            'options': {'multi_result': true},
          },
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isError, isTrue);
        expect(response.error!.code, RpcErrorCode.invalidParams);
        verifyNever(() => mockGateway.executeQuery(any()));
      },
    );

    test(
      'should pass pagination to gateway and return pagination metadata',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT * FROM users ORDER BY id',
            'options': {'page': 2, 'page_size': 25},
          },
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [
            {'id': 26},
          ],
          timestamp: DateTime.now(),
          pagination: const QueryPaginationInfo(
            page: 2,
            pageSize: 25,
            returnedRows: 1,
            hasNextPage: true,
            hasPreviousPage: true,
          ),
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(
          () => mockNormalizer.normalize(any()),
        ).thenAnswer((_) => queryResponse);

        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          limits: const TransportLimits(maxRows: 100),
        );

        expect(response.isSuccess, isTrue);
        final captured =
            verify(() => mockGateway.executeQuery(captureAny())).captured.single
                as QueryRequest;
        expect(captured.pagination, isNotNull);
        expect(captured.pagination!.page, 2);
        expect(captured.pagination!.pageSize, 25);

        final result = response.result as Map<String, dynamic>;
        expect(result['sql_handling_mode'], 'managed');
        expect(result['pagination'], isA<Map<String, dynamic>>());
        expect((result['pagination'] as Map<String, dynamic>)['page'], 2);
      },
    );

    test('should allow offset pagination without explicit order by', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'SELECT * FROM users',
          'options': {'page': 1, 'page_size': 25},
        },
      );

      final queryResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'id': 1},
        ],
        timestamp: DateTime.now(),
        pagination: const QueryPaginationInfo(
          page: 1,
          pageSize: 25,
          returnedRows: 1,
          hasNextPage: true,
          hasPreviousPage: false,
        ),
      );
      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse));
      when(
        () => mockNormalizer.normalize(any()),
      ).thenAnswer((_) => queryResponse);

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      final captured =
          verify(() => mockGateway.executeQuery(captureAny())).captured.single
              as QueryRequest;
      expect(captured.pagination, isNotNull);
      expect(captured.pagination!.orderBy, isEmpty);
    });

    test('should reject cursor pagination without explicit order by', () async {
      final response = await dispatcher.dispatch(
        const RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT * FROM users',
            'options': {'cursor': 'YWJj'},
          },
        ),
        'agent-1',
      );

      expect(response.isError, isTrue);
      expect(response.error!.code, RpcErrorCode.invalidParams);
      final data = response.error!.data as Map<String, dynamic>;
      expect(
        data['technical_message'],
        'Paginated queries must declare an explicit ORDER BY clause',
      );
      verifyNever(() => mockGateway.executeQuery(any()));
    });

    test(
      'should pass execution_mode preserve to gateway without managed pagination',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT * FROM users LIMIT 10',
            'options': {'execution_mode': 'preserve'},
          },
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [
            {'id': 1},
          ],
          timestamp: DateTime.now(),
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(
          () => mockNormalizer.normalize(any()),
        ).thenAnswer((_) => queryResponse);

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isSuccess, isTrue);
        final result = response.result as Map<String, dynamic>;
        expect(result['sql_handling_mode'], 'preserve');
        expect(result['max_rows_handling'], 'response_truncation');
        final captured =
            verify(() => mockGateway.executeQuery(captureAny())).captured.single
                as QueryRequest;
        expect(captured.preserveSql, isTrue);
        expect(captured.sqlHandlingMode, SqlHandlingMode.preserve);
        expect(captured.pagination, isNull);
      },
    );

    test(
      'should reject execution_mode preserve combined with pagination options',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: {
            'sql': 'SELECT * FROM users ORDER BY id',
            'options': {
              'execution_mode': 'preserve',
              'page': 1,
              'page_size': 25,
            },
          },
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isError, isTrue);
        expect(response.error!.code, RpcErrorCode.invalidParams);
        final data = response.error!.data as Map<String, dynamic>;
        expect(
          data['technical_message'],
          'execution_mode "preserve" cannot be combined with page, page_size, or cursor',
        );
        verifyNever(() => mockGateway.executeQuery(any()));
      },
    );

    test('should accept deprecated preserve_sql alias', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'SELECT * FROM users LIMIT 10',
          'options': {'preserve_sql': true},
        },
      );

      final queryResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'id': 1},
        ],
        timestamp: DateTime.now(),
      );

      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse));
      when(
        () => mockNormalizer.normalize(any()),
      ).thenAnswer((_) => queryResponse);

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      final captured =
          verify(() => mockGateway.executeQuery(captureAny())).captured.single
              as QueryRequest;
      expect(captured.sqlHandlingMode, SqlHandlingMode.preserve);
    });

    test(
      'should decode cursor pagination and return next cursor metadata',
      () async {
        final paginationPlan = SqlValidator.validatePaginationQuery(
          'SELECT * FROM users ORDER BY id',
        ).getOrNull()!;
        final cursor = QueryPaginationCursor(
          page: 3,
          pageSize: 25,
          queryHash: paginationPlan.queryFingerprint,
          orderBy: paginationPlan.orderBy,
          lastRowValues: [50],
        ).toToken();
        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [
            {'id': 51},
          ],
          timestamp: DateTime.now(),
          pagination: const QueryPaginationInfo(
            page: 3,
            pageSize: 25,
            returnedRows: 1,
            hasNextPage: true,
            hasPreviousPage: true,
            currentCursor: 'cursor-current',
            nextCursor: 'cursor-next',
          ),
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(
          () => mockNormalizer.normalize(any()),
        ).thenAnswer((_) => queryResponse);

        final response = await dispatcher.dispatch(
          RpcRequest(
            jsonrpc: '2.0',
            method: 'sql.execute',
            id: 'req-1',
            params: {
              'sql': 'SELECT * FROM users ORDER BY id',
              'options': {'cursor': cursor},
            },
          ),
          'agent-1',
        );

        expect(response.isSuccess, isTrue);
        final captured =
            verify(() => mockGateway.executeQuery(captureAny())).captured.single
                as QueryRequest;
        expect(captured.pagination, isNotNull);
        expect(captured.pagination!.cursor, cursor);
        expect(captured.pagination!.usesStableCursor, isTrue);
        expect(captured.pagination!.lastRowValues, [50]);
        final result = response.result as Map<String, dynamic>;
        expect(
          (result['pagination'] as Map<String, dynamic>)['next_cursor'],
          'cursor-next',
        );
      },
    );

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
                  as Future<void> Function(List<Map<String, dynamic>>);
          await onChunk([
            {'id': 1, 'name': 'a'},
            {'id': 2, 'name': 'b'},
          ]);
          await onChunk([
            {'id': 3, 'name': 'c'},
          ]);
          return const Success(unit);
        });

        dispatcher = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          normalizerService: mockNormalizer,
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
        when(() => mockEmitter.emitChunk(any())).thenAnswer((_) async => true);
        when(() => mockEmitter.emitComplete(any())).thenAnswer((_) async {});
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
      'should skip DB streaming path when paginated request is provided',
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

        dispatcher = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          featureFlags: mockFeatureFlags,
          configRepository: mockConfigRepo,
          streamingGateway: mockStreamingGateway,
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [
            {'id': 1},
          ],
          timestamp: DateTime.now(),
          pagination: const QueryPaginationInfo(
            page: 1,
            pageSize: 50,
            returnedRows: 1,
            hasNextPage: false,
            hasPreviousPage: false,
          ),
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
          params: {
            'sql': 'SELECT * FROM users ORDER BY id',
            'options': {'page': 1, 'page_size': 50},
          },
        );

        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          streamEmitter: _stubRpcStreamEmitter(),
        );

        expect(response.isSuccess, isTrue);
        verifyNever(
          () => mockStreamingGateway.executeQueryStream(
            any(),
            any(),
            any(),
            fetchSize: any(named: 'fetchSize'),
            chunkSizeBytes: any(named: 'chunkSizeBytes'),
          ),
        );
        verify(() => mockGateway.executeQuery(any())).called(1);
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
        ).thenAnswer((_) => queryResponse);

        final mockEmitter = MockRpcStreamEmitter();
        when(() => mockEmitter.emitChunk(any())).thenAnswer((_) async => true);
        when(() => mockEmitter.emitComplete(any())).thenAnswer((_) async {});
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
        (invocation) => invocation.positionalArguments[0] as QueryResponse,
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      final result = response.result as Map<String, dynamic>;
      expect(result['items'], hasLength(2));
      expect(result['total_commands'], equals(2));
    });

    test(
      'should cap sql.executeBatch ODBC timeout with options.timeout_ms when '
      'stage budgets are enabled',
      () async {
        when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(true);

        final captured = <Duration?>[];
        when(
          () => mockGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
            database: any(named: 'database'),
          ),
        ).thenAnswer((invocation) async {
          const sym = Symbol('timeout');
          captured.add(
            invocation.namedArguments.containsKey(sym)
                ? invocation.namedArguments[sym] as Duration?
                : null,
          );
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return Success(
            QueryResponse(
              id: 'e',
              requestId: 'r',
              agentId: 'agent-1',
              data: const [],
              timestamp: DateTime.now(),
            ),
          );
        });
        when(() => mockNormalizer.normalize(any())).thenAnswer(
          (invocation) =>
              invocation.positionalArguments[0] as QueryResponse,
        );

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'req-1',
          params: {
            'commands': [
              {'sql': 'SELECT 1'},
              {'sql': 'SELECT 2'},
            ],
            'options': {
              'timeout_ms': 8000,
              'transaction': false,
            },
          },
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isSuccess, isTrue);
        expect(captured, hasLength(2));
        expect(captured[0], isNotNull);
        final first = captured[0]!;
        expect(first.inMilliseconds, lessThanOrEqualTo(8000));
        expect(captured[1], isNotNull);
        final second = captured[1]!;
        expect(second.inMilliseconds, lessThanOrEqualTo(8000));
        expect(second, lessThan(first));
      },
    );

    test(
      'should deduplicate batch authorization checks for equivalent SQL commands',
      () async {
        when(
          () => mockFeatureFlags.enableClientTokenAuthorization,
        ).thenReturn(true);
        when(
          () => mockAuthorize(
            token: any(named: 'token'),
            sql: any(named: 'sql'),
            requestId: any(named: 'requestId'),
            method: any(named: 'method'),
          ),
        ).thenAnswer((_) async => const Success(unit));

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'req-1',
          params: {
            'commands': [
              {'sql': 'SELECT * FROM users WHERE id = 1'},
              {'sql': ' SELECT  *  FROM users WHERE id = 1 '},
            ],
          },
        );

        final queryResponse = QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [
            {'id': 1, 'name': 'John'},
          ],
          timestamp: DateTime.now(),
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((_) async => Success(queryResponse));
        when(() => mockNormalizer.normalize(any())).thenAnswer(
          (invocation) =>
              invocation.positionalArguments[0] as QueryResponse,
        );

        final response = await dispatcher.dispatch(
          request,
          'agent-1',
          clientToken: 'token-abc',
        );

        check(response.isSuccess).isTrue();
        verify(
          () => mockAuthorize(
            token: any(named: 'token'),
            sql: any(named: 'sql'),
            requestId: any(named: 'requestId'),
            method: any(named: 'method'),
          ),
        ).called(1);
      },
    );

    test(
      'should execute sql.executeBatch following optional execution_order',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'req-1',
          params: {
            'commands': [
              {'sql': 'SELECT * FROM users WHERE id = 2', 'execution_order': 2},
              {'sql': 'SELECT * FROM users WHERE id = 1', 'execution_order': 1},
              {'sql': 'SELECT * FROM users WHERE id = 3'},
            ],
          },
        );

        var callCount = 0;
        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((invocation) async {
          callCount++;
          final query = invocation.positionalArguments[0] as QueryRequest;
          return Success(
            QueryResponse(
              id: 'exec-$callCount',
              requestId: 'req-1',
              agentId: 'agent-1',
              data: [
                {'sql': query.query},
              ],
              timestamp: DateTime.now(),
            ),
          );
        });
        when(() => mockNormalizer.normalize(any())).thenAnswer(
          (invocation) =>
              invocation.positionalArguments[0] as QueryResponse,
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        check(response.isSuccess).isTrue();
        final captured = verify(
          () => mockGateway.executeQuery(captureAny()),
        ).captured.cast<QueryRequest>();
        check(
          captured.map((query) => query.query).join('|'),
        ).equals(
          'SELECT * FROM users WHERE id = 1|SELECT * FROM users '
          'WHERE id = 2|SELECT * FROM users WHERE id = 3',
        );

        final result = response.result as Map<String, dynamic>;
        final items = (result['items'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        check(items.map((item) => item['index']).join(',')).equals('0,1,2');
      },
    );

    test(
      'should execute explicit execution_order commands before unordered ones',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'req-1',
          params: {
            'commands': [
              {
                'sql': 'SELECT * FROM users WHERE id = 10',
                'execution_order': 10,
              },
              {'sql': 'SELECT * FROM users WHERE id = 20'},
              {'sql': 'SELECT * FROM users WHERE id = 1', 'execution_order': 1},
            ],
          },
        );

        when(
          () => mockGateway.executeQuery(any()),
        ).thenAnswer((invocation) async {
          final query = invocation.positionalArguments[0] as QueryRequest;
          return Success(
            QueryResponse(
              id: 'exec-1',
              requestId: 'req-1',
              agentId: 'agent-1',
              data: [
                {'sql': query.query},
              ],
              timestamp: DateTime.now(),
            ),
          );
        });
        when(() => mockNormalizer.normalize(any())).thenAnswer(
          (invocation) =>
              invocation.positionalArguments[0] as QueryResponse,
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        check(response.isSuccess).isTrue();
        final captured = verify(
          () => mockGateway.executeQuery(captureAny()),
        ).captured.cast<QueryRequest>();
        check(captured.map((query) => query.query).join('|')).equals(
          [
            'SELECT * FROM users WHERE id = 1',
            'SELECT * FROM users WHERE id = 10',
            'SELECT * FROM users WHERE id = 20',
          ].join('|'),
        );
      },
    );

    test(
      'should return invalidParams when batch execution_order is invalid',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'req-1',
          params: {
            'commands': [
              {'sql': 'SELECT 1', 'execution_order': -1},
            ],
          },
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        check(response.isError).isTrue();
        check(response.error!.code).equals(RpcErrorCode.invalidParams);
        verifyNever(() => mockGateway.executeQuery(any()));
      },
    );

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
      'should map transactional batch failure to transactionFailed',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.executeBatch',
          id: 'req-1',
          params: {
            'commands': [
              {'sql': 'UPDATE users SET active = 1'},
              {'sql': 'UPDATE users SET active = 0'},
            ],
            'options': {'transaction': true},
          },
        );

        when(
          () => mockGateway.executeBatch(
            any(),
            any(),
            database: any(named: 'database'),
            options: any(named: 'options'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Transaction aborted',
              context: {'reason': 'transaction_failed'},
            ),
          ),
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        check(response.isError).isTrue();
        check(response.error!.code).equals(RpcErrorCode.transactionFailed);
      },
    );

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
            requestId: any(named: 'requestId'),
            method: any(named: 'method'),
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

    test('should return unauthorized on authorization stage timeout', () async {
      when(
        () => mockFeatureFlags.enableClientTokenAuthorization,
      ).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(true);
      when(
        () => mockAuthorize(
          token: any(named: 'token'),
          sql: any(named: 'sql'),
          requestId: any(named: 'requestId'),
          method: any(named: 'method'),
        ),
      ).thenAnswer(
        (_) => Future<Result<void>>.delayed(
          const Duration(milliseconds: 60),
          () => const Success(unit),
        ),
      );

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        featureFlags: mockFeatureFlags,
        streamingGateway: mockStreamingGateway,
        sqlExecuteTotalBudget: const Duration(milliseconds: 80),
        authorizationStageBudget: const Duration(milliseconds: 10),
      );

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-timeout',
        params: {
          'sql': 'SELECT * FROM dbo.users',
          'client_token': 'bearer-timeout',
        },
      );

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        clientToken: 'bearer-timeout',
      );

      expect(response.isError, isTrue);
      expect(response.error!.code, equals(RpcErrorCode.unauthorized));
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['reason'], equals('authorization_timeout'));
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

    test(
      'should return cached response when idempotency key repeats',
      () async {
        final mockStore = MockIdempotencyStore();
        when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

        dispatcher = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          normalizerService: mockNormalizer,
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
        ).thenAnswer((_) => queryResponse);

        when(() => mockStore.getRecord(any())).thenReturn(null);

        final first = await dispatcher.dispatch(request, 'agent-1');

        expect(first.isSuccess, isTrue);

        when(
          () => mockStore.getRecord(any()),
        ).thenReturn(
          IdempotencyRecord(
            response: first,
            requestFingerprint: null,
          ),
        );

        final second = await dispatcher.dispatch(request, 'agent-1');

        expect(second.isSuccess, isTrue);
        expect(second.result, equals(first.result));
      },
    );

    test(
      'should reject idempotency key reuse with different payload fingerprint',
      () async {
        final mockStore = MockIdempotencyStore();
        var mismatchCount = 0;
        when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

        dispatcher = RpcMethodDispatcher(
          databaseGateway: mockGateway,
          normalizerService: mockNormalizer,
          uuid: const Uuid(),
          authorizeSqlOperation: mockAuthorize,
          featureFlags: mockFeatureFlags,
          idempotencyStore: mockStore,
          onIdempotencyFingerprintMismatch: () => mismatchCount++,
          streamingGateway: mockStreamingGateway,
        );

        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-1',
          params: <String, dynamic>{
            'sql': 'SELECT 2',
            'idempotency_key': 'key-abc',
          },
        );

        when(
          () => mockStore.getRecord(any()),
        ).thenReturn(
          IdempotencyRecord(
            response: RpcResponse.success(
              id: 'req-1',
              result: const <String, dynamic>{'x': 1},
            ),
            requestFingerprint: 'different-fingerprint',
          ),
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        check(response.isError).isTrue();
        check(response.error!.code).equals(RpcErrorCode.invalidParams);
        check(mismatchCount).equals(1);
        verifyNever(() => mockGateway.executeQuery(any()));
      },
    );

    test('should ignore idempotency cache for notifications', () async {
      final mockStore = MockIdempotencyStore();
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(true);

      dispatcher = RpcMethodDispatcher(
        databaseGateway: mockGateway,
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        featureFlags: mockFeatureFlags,
        idempotencyStore: mockStore,
        streamingGateway: mockStreamingGateway,
      );

      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: null,
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
      ).thenAnswer((_) => queryResponse);

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      verifyNever(() => mockStore.getRecord(any()));
      verifyNever(
        () => mockStore.set(
          any(),
          any(),
          any(),
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      );
    });

    test('should cap rows using negotiated maxRows', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: {
          'sql': 'SELECT * FROM users',
          'options': {'max_rows': 10},
        },
      );

      final queryResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: List.generate(20, _userAt),
        timestamp: DateTime.now(),
      );

      when(
        () => mockGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(queryResponse));
      when(
        () => mockNormalizer.normalize(any()),
      ).thenAnswer((_) => queryResponse);

      final response = await dispatcher.dispatch(
        request,
        'agent-1',
        limits: const TransportLimits(maxRows: 5),
      );

      expect(response.isSuccess, isTrue);
      final result = response.result as Map<String, dynamic>;
      expect((result['rows'] as List<dynamic>).length, 5);
      expect(result['truncated'], isTrue);
      expect(result['effective_max_rows'], 5);
    });

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
            () => mockFeatureFlags.enableSocketStreamingChunks,
          ).thenReturn(true);
          when(
            () => mockFeatureFlags.enableSocketStreamingFromDb,
          ).thenReturn(true);
          when(
            () => mockFeatureFlags.enableSocketCancelMethod,
          ).thenReturn(true);
          when(() => mockStreamingGateway.hasActiveStream).thenReturn(true);
          when(
            () => mockStreamingGateway.cancelActiveStream(
              reason: any(named: 'reason'),
            ),
          ).thenAnswer((_) async => const Success(unit));

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

          final completer = Completer<Result<void>>();
          when(
            () => mockStreamingGateway.executeQueryStream(
              any(),
              any(),
              any(),
              fetchSize: any(named: 'fetchSize'),
              chunkSizeBytes: any(named: 'chunkSizeBytes'),
            ),
          ).thenAnswer((_) => completer.future);

          dispatcher = RpcMethodDispatcher(
            databaseGateway: mockGateway,
            normalizerService: mockNormalizer,
            uuid: const Uuid(),
            authorizeSqlOperation: mockAuthorize,
            featureFlags: mockFeatureFlags,
            configRepository: mockConfigRepo,
            streamingGateway: mockStreamingGateway,
          );

          final dispatchFuture = dispatcher.dispatch(
            const RpcRequest(
              jsonrpc: '2.0',
              method: 'sql.execute',
              id: 'req-1',
              params: {'sql': 'SELECT * FROM users'},
            ),
            'agent-1',
            streamEmitter: _stubRpcStreamEmitter(),
          );

          await Future<void>.delayed(Duration.zero);

          final response = await dispatcher.dispatch(
            const RpcRequest(
              jsonrpc: '2.0',
              method: 'sql.cancel',
              id: 'req-cancel',
              params: {
                'request_id': 'req-1',
              },
            ),
            'agent-1',
          );

          expect(response.isSuccess, isTrue);
          final result = response.result as Map<String, dynamic>;
          expect(result['cancelled'], isTrue);
          expect(result['request_id'], equals('req-1'));
          verify(() => mockStreamingGateway.cancelActiveStream()).called(1);

          completer.complete(const Success(unit));
          await dispatchFuture;
        },
      );

      test(
        'should return executionNotFound when ids do not match active stream',
        () async {
          when(
            () => mockFeatureFlags.enableSocketStreamingChunks,
          ).thenReturn(true);
          when(
            () => mockFeatureFlags.enableSocketStreamingFromDb,
          ).thenReturn(true);
          when(
            () => mockFeatureFlags.enableSocketCancelMethod,
          ).thenReturn(true);
          when(() => mockStreamingGateway.hasActiveStream).thenReturn(true);

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

          final completer = Completer<Result<void>>();
          when(
            () => mockStreamingGateway.executeQueryStream(
              any(),
              any(),
              any(),
              fetchSize: any(named: 'fetchSize'),
              chunkSizeBytes: any(named: 'chunkSizeBytes'),
            ),
          ).thenAnswer((_) => completer.future);

          dispatcher = RpcMethodDispatcher(
            databaseGateway: mockGateway,
            normalizerService: mockNormalizer,
            uuid: const Uuid(),
            authorizeSqlOperation: mockAuthorize,
            featureFlags: mockFeatureFlags,
            configRepository: mockConfigRepo,
            streamingGateway: mockStreamingGateway,
          );

          final dispatchFuture = dispatcher.dispatch(
            const RpcRequest(
              jsonrpc: '2.0',
              method: 'sql.execute',
              id: 'req-stream',
              params: {'sql': 'SELECT * FROM users'},
            ),
            'agent-1',
            streamEmitter: _stubRpcStreamEmitter(),
          );

          await Future<void>.delayed(Duration.zero);

          final cancelResponse = await dispatcher.dispatch(
            const RpcRequest(
              jsonrpc: '2.0',
              method: 'sql.cancel',
              id: 'req-cancel',
              params: {'request_id': 'another-request'},
            ),
            'agent-1',
          );

          expect(cancelResponse.isError, isTrue);
          expect(
            cancelResponse.error!.code,
            equals(RpcErrorCode.executionNotFound),
          );
          verifyNever(() => mockStreamingGateway.cancelActiveStream());

          completer.complete(const Success(unit));
          await dispatchFuture;
        },
      );
    });

    test(
      'cancelActiveStreamOnDisconnect should cancel gateway when active stream exists',
      () async {
        when(() => mockStreamingGateway.hasActiveStream).thenReturn(true);
        when(
          () => mockStreamingGateway.cancelActiveStream(
            reason: any(named: 'reason'),
          ),
        ).thenAnswer((_) async => const Success(unit));

        await dispatcher.cancelActiveStreamOnDisconnect();

        verify(
          () => mockStreamingGateway.cancelActiveStream(
            reason: StreamingCancelReason.socketDisconnect,
          ),
        ).called(1);
      },
    );

    test(
      'cancelActiveStreamOnDisconnect should do nothing when no active stream',
      () async {
        when(() => mockStreamingGateway.hasActiveStream).thenReturn(false);

        await dispatcher.cancelActiveStreamOnDisconnect();

        verifyNever(() => mockStreamingGateway.cancelActiveStream());
      },
    );
  });
}
