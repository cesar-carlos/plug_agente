import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';
import 'package:plug_agente/application/rpc/sql_rpc_db_streaming_executor.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/query/prepared_query_execution.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/i_streaming_named_parameter_preparer.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class _PassthroughStreamingNamedParameterPreparer implements IStreamingNamedParameterPreparer {
  @override
  Result<OdbcPreparedQueryExecution> prepare({
    required String sql,
    Map<String, dynamic>? parameters,
  }) {
    return Success(
      OdbcPreparedQueryExecution(sql: sql, parameters: parameters),
    );
  }
}

class _CapturingStreamingGateway implements IStreamingDatabaseGateway {
  String? lastConnectionString;

  @override
  bool get hasActiveStream => false;

  @override
  Future<Result<void>> cancelActiveStream({
    String? executionId,
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) async {
    return const Success(unit);
  }

  @override
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    Future<void> Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 100,
    int chunkSizeBytes = 65536,
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
    Future<void> Function(StreamingWireChunk chunk)? onWireChunk,
    void Function()? onSetupComplete,
    Map<String, dynamic>? parameters,
    bool columnarWireOnly = false,
  }) async {
    lastConnectionString = connectionString;
    await onChunk(const <Map<String, dynamic>>[
      <String, dynamic>{'id': 1},
    ]);
    return const Success(unit);
  }

  @override
  Future<Result<void>> executeMultiResultQueryStream(
    String query,
    String connectionString,
    Future<void> Function(StreamingWireChunk chunk) onWireChunk, {
    String? executionId,
    Duration? queryTimeout,
    CancellationToken? cancellationToken,
    StreamingCancelReason? Function()? cancellationReasonProvider,
    void Function()? onSetupComplete,
  }) {
    throw UnimplementedError();
  }
}

class _AcceptingStreamEmitter implements IRpcStreamEmitter {
  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async => true;

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {}
}

SqlRpcMethodHandlerSupport _support() {
  return SqlRpcMethodHandlerSupport(
    invalidParams: (_, detail, {rpcReason, extraFields = const {}}) => throw UnimplementedError(),
    methodNotFound: (_) => throw UnimplementedError(),
    executionNotFound: (_) => throw UnimplementedError(),
    consumeIdempotentCacheIfAny: (_, key, fingerprint) async => null,
    storeIdempotentSuccessIfApplicable:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required response,
        }) async {},
    runIdempotentExecution:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required execute,
          idempotentCachePrefetched = false,
        }) => execute(),
    buildMissingClientTokenFailure: () => throw UnimplementedError(),
    authorizeWithBudget:
        ({
          required token,
          required sql,
          required requestDatabase,
          required requestId,
          required method,
          required deadline,
        }) async => const Success(unit),
    effectiveStageTimeout: ({required deadline, required stageBudget}) => stageBudget,
  );
}

void main() {
  late MockAgentConfigRepository repository;
  late ActiveConfigResolver resolver;
  late MockFeatureFlags featureFlags;
  late _CapturingStreamingGateway gateway;
  late SqlRpcDbStreamingExecutor executor;

  final now = DateTime.utc(2026, 6, 15);
  final fullConfig = Config(
    id: 'cfg-1',
    agentId: 'agent-1',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=demo;UID=sa',
    username: 'sa',
    password: 'db-secret',
    databaseName: 'demo',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    repository = MockAgentConfigRepository();
    resolver = ActiveConfigResolver(repository, InMemoryAppSettingsStore());
    featureFlags = MockFeatureFlags();
    gateway = _CapturingStreamingGateway();

    when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(true);
    when(() => featureFlags.enableSocketStreamingChunks).thenReturn(true);
    when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => repository.getCurrentConfig()).thenAnswer((_) async => Success(fullConfig));
    when(() => repository.getById('cfg-1')).thenAnswer((_) async => Success(fullConfig));

    executor = SqlRpcDbStreamingExecutor(
      featureFlags: featureFlags,
      support: _support(),
      sqlStreamingCoordinator: SqlStreamingCoordinator(gateway: gateway),
      autoPolicy: SqlDbStreamingAutoPolicy(),
      terminalEmitter: const SqlRpcStreamTerminalEmitter(),
      uuid: const Uuid(),
      sqlExecuteTotalBudget: const Duration(seconds: 30),
      streamingNamedParameterPreparer: _PassthroughStreamingNamedParameterPreparer(),
      activeConfigResolver: resolver,
      streamingGateway: gateway,
    );
  });

  group('SqlRpcDbStreamingExecutor config resolution', () {
    test('uses full config with secure password and hub database override', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: <String, dynamic>{
          'sql': 'SELECT * FROM users',
          'database': 'hub_target_db',
        },
      );
      final queryRequest = QueryRequest(
        id: 'q-1',
        agentId: 'agent-1',
        query: 'SELECT * FROM users',
        timestamp: now,
      );

      final response = await executor.tryStreamingFromDb(
        request,
        queryRequest,
        'SELECT * FROM users',
        _AcceptingStreamEmitter(),
        limits: const TransportLimits(streamingRowThreshold: 10),
        deadline: DateTime.now().add(const Duration(seconds: 30)),
        timeoutMs: 0,
        negotiatedExtensions: const <String, dynamic>{'streamingResults': true},
        preferDbStreaming: true,
        effectiveMaxRows: 10_000,
        database: 'hub_target_db',
      );

      expect(response, isNotNull);
      expect(response!.isSuccess, isTrue);
      expect(gateway.lastConnectionString, isNotNull);
      expect(gateway.lastConnectionString, contains('PWD=db-secret'));
      expect(gateway.lastConnectionString, contains('DATABASE=hub_target_db'));
      expect(gateway.lastConnectionString, isNot(contains('DATABASE=demo')));
      verify(() => repository.getCurrentConfig()).called(1);
      verifyNever(() => repository.getCurrentConfigMetadata());
      verifyNever(() => repository.getByIdMetadata(any()));
    });
  });
}
