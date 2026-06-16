import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';
import 'package:plug_agente/application/rpc/sql_rpc_db_streaming_executor.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
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

import '../../tool/benchmarks/benchmark_plug_agente_stack.dart' as benchmark;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(QueryRequest(
      id: 'fallback',
      agentId: 'agent-1',
      query: 'SELECT 1',
      timestamp: DateTime.utc(2026, 6, 16),
    ));
  });

  test(
    'builds plug_agente stack benchmark report',
    () async {
      final report = await benchmark.buildPlugAgenteStackBenchmarkReport(
        configCacheIterations: 200,
        connectionStringIterations: 300,
        columnarRowCount: 4000,
        columnarIterations: 6,
        backpressureChunkCount: 60,
        queuedGatewayIterations: 80,
      );

      stdout.writeln(report);

      expect(report, contains('# Plug Agente Stack Benchmark'));
      expect(report, contains('config_metadata_cache'));
      expect(report, contains('odbc_connection_string_ttl_cache'));
      expect(report, contains('columnar_stream_emitter'));
      expect(report, contains('backpressure_stream_emitter'));
      expect(report, contains('queued_database_gateway'));

      final sqlRpcReport = await _buildSqlRpcStreamingBenchmarkReport(iterations: 40);
      stdout.writeln(sqlRpcReport);
      expect(sqlRpcReport, contains('sql_rpc_db_streaming_executor'));
    },
    timeout: Timeout.none,
    tags: const ['perf'],
  );

  test(
    'emits plug_agente stack benchmark json',
    () async {
      final rows = await benchmark.buildPlugAgenteStackBenchmarkRows(
        configCacheIterations: 50,
        connectionStringIterations: 80,
        columnarRowCount: 1000,
        columnarIterations: 3,
        backpressureChunkCount: 20,
        queuedGatewayIterations: 20,
      );
      final payload = benchmark.buildPlugAgenteStackBenchmarkJson(rows: rows);

      stdout.writeln(jsonEncode(payload));

      expect(payload['benchmark'], 'plug_agente_stack');
      final encodedRows = payload['rows']! as List<dynamic>;
      expect(encodedRows, isNotEmpty);
      expect(encodedRows.first, containsPair('scenario', isA<String>()));
    },
    timeout: Timeout.none,
    tags: const ['perf'],
  );
}

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class _PassthroughStreamingNamedParameterPreparer implements IStreamingNamedParameterPreparer {
  @override
  Result<OdbcPreparedQueryExecution> prepare({
    required String sql,
    Map<String, dynamic>? parameters,
  }) {
    return Success(OdbcPreparedQueryExecution(sql: sql, parameters: parameters));
  }
}

class _BenchmarkStreamingGateway implements IStreamingDatabaseGateway {
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
    await onChunk(const [
      {'id': 1},
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

SqlRpcMethodHandlerSupport _benchmarkSupport() {
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

Future<String> _buildSqlRpcStreamingBenchmarkReport({required int iterations}) async {
  final repository = _MockAgentConfigRepository();
  final resolver = ActiveConfigResolver(repository, InMemoryAppSettingsStore());
  final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
  await featureFlags.setEnableSocketStreamingFromDb(true);
  await featureFlags.setEnableSocketStreamingChunks(true);
  await featureFlags.setEnableSocketTimeoutByStage(false);

  final now = DateTime.utc(2026, 6, 16);
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

  when(repository.getCurrentConfig).thenAnswer((_) async => Success(fullConfig));
  when(() => repository.getById('cfg-1')).thenAnswer((_) async => Success(fullConfig));

  final configCache = ActiveConfigMetadataCache(activeConfigResolver: resolver);
  final gateway = _BenchmarkStreamingGateway();
  final executor = SqlRpcDbStreamingExecutor(
    featureFlags: featureFlags,
    support: _benchmarkSupport(),
    sqlStreamingCoordinator: SqlStreamingCoordinator(gateway: gateway),
    autoPolicy: SqlDbStreamingAutoPolicy(),
    terminalEmitter: const SqlRpcStreamTerminalEmitter(),
    uuid: const Uuid(),
    sqlExecuteTotalBudget: const Duration(seconds: 30),
    streamingNamedParameterPreparer: _PassthroughStreamingNamedParameterPreparer(),
    activeConfigResolver: resolver,
    configQueryCache: configCache,
    streamingGateway: gateway,
  );

  const request = RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.execute',
    id: 'req-bench',
    params: <String, dynamic>{
      'sql': 'SELECT * FROM users',
      'database': 'hub_target_db',
    },
  );
  final queryRequest = QueryRequest(
    id: 'q-bench',
    agentId: 'agent-1',
    query: 'SELECT * FROM users',
    timestamp: now,
  );

  Future<int> measure({required bool warmCache}) async {
    if (!warmCache) {
      configCache.invalidate();
    }
    final samples = <int>[];
    for (var i = 0; i < iterations; i++) {
      final stopwatch = Stopwatch()..start();
      final tryResult = await executor.tryStreamingFromDb(
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
      stopwatch.stop();
      expect(tryResult.succeeded, isTrue);
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  final coldMedian = await measure(warmCache: false);
  final warmMedian = await measure(warmCache: true);
  final speedup = warmMedian <= 0 ? '-' : (coldMedian / warmMedian).toStringAsFixed(2);

  return '''
| scenario | variant | iterations | median_us | p95_us | speedup | rows_per_sec | notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| sql_rpc_db_streaming_executor | cold_config_cache | $iterations | $coldMedian | - | - | - | integrated_mock_path |
| sql_rpc_db_streaming_executor | warm_config_cache | $iterations | $warmMedian | - | $speedup | - | integrated_mock_path |
''';
}
