
import 'dart:convert';
import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/cache/odbc_connection_string_ttl_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_emitter.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';
import 'package:result_dart/result_dart.dart';

const String _reportHeader = '# Plug Agente Stack Benchmark';

class PlugAgenteStackBenchmarkRow {
  const PlugAgenteStackBenchmarkRow({
    required this.scenario,
    required this.variant,
    required this.iterations,
    required this.medianUs,
    this.p95Us,
    this.speedup,
    this.rowsPerSec,
    this.notes = '',
  });

  final String scenario;
  final String variant;
  final int iterations;
  final int medianUs;
  final int? p95Us;
  final double? speedup;
  final double? rowsPerSec;
  final String notes;

  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'variant': variant,
    'iterations': iterations,
    'median_us': medianUs,
    if (p95Us != null) 'p95_us': p95Us,
    if (speedup != null) 'speedup': speedup,
    if (rowsPerSec != null) 'rows_per_sec': rowsPerSec,
    if (notes.isNotEmpty) 'notes': notes,
  };
}

Future<List<PlugAgenteStackBenchmarkRow>> buildPlugAgenteStackBenchmarkRows({
  int configCacheIterations = 300,
  int connectionStringIterations = 500,
  int columnarRowCount = 5000,
  int columnarIterations = 8,
  int backpressureChunkCount = 80,
  int backpressureEmitDelayUs = 150,
  int queuedGatewayIterations = 120,
}) async {
  final rows = <PlugAgenteStackBenchmarkRow>[];

  rows.addAll(
    await _benchmarkConfigMetadataCache(iterations: configCacheIterations),
  );
  rows.addAll(
    _benchmarkConnectionStringTtlCache(iterations: connectionStringIterations),
  );
  rows.addAll(
    await _benchmarkColumnarEmitter(
      rowCount: columnarRowCount,
      iterations: columnarIterations,
    ),
  );
  rows.addAll(
    await _benchmarkBackpressureEmitter(
      chunkCount: backpressureChunkCount,
      emitDelayUs: backpressureEmitDelayUs,
    ),
  );
  rows.addAll(
    await _benchmarkQueuedDatabaseGateway(iterations: queuedGatewayIterations),
  );

  return rows;
}

Future<String> buildPlugAgenteStackBenchmarkReport({
  int configCacheIterations = 300,
  int connectionStringIterations = 500,
  int columnarRowCount = 5000,
  int columnarIterations = 8,
  int backpressureChunkCount = 80,
  int backpressureEmitDelayUs = 150,
  int queuedGatewayIterations = 120,
}) async {
  final rows = await buildPlugAgenteStackBenchmarkRows(
    configCacheIterations: configCacheIterations,
    connectionStringIterations: connectionStringIterations,
    columnarRowCount: columnarRowCount,
    columnarIterations: columnarIterations,
    backpressureChunkCount: backpressureChunkCount,
    backpressureEmitDelayUs: backpressureEmitDelayUs,
    queuedGatewayIterations: queuedGatewayIterations,
  );
  return _formatMarkdownReport(rows);
}

Map<String, Object?> buildPlugAgenteStackBenchmarkJson({
  required List<PlugAgenteStackBenchmarkRow> rows,
}) {
  return {
    'benchmark': 'plug_agente_stack',
    'rows': rows.map((row) => row.toJson()).toList(growable: false),
  };
}

String _formatMarkdownReport(List<PlugAgenteStackBenchmarkRow> rows) {
  final buffer = StringBuffer()
    ..writeln(_reportHeader)
    ..writeln()
    ..writeln(
      '| scenario | variant | iterations | median_us | p95_us | speedup | rows_per_sec | notes |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |');

  for (final row in rows) {
    buffer.writeln(
      '| ${row.scenario} | ${row.variant} | ${row.iterations} | '
      '${row.medianUs} | ${_formatOptionalInt(row.p95Us)} | '
      '${_formatOptionalDouble(row.speedup)} | '
      '${_formatOptionalDouble(row.rowsPerSec)} | ${row.notes} |',
    );
  }

  return buffer.toString();
}

String _formatOptionalInt(int? value) => value == null ? '-' : '$value';

String _formatOptionalDouble(double? value) {
  if (value == null) {
    return '-';
  }
  return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
}

Future<List<PlugAgenteStackBenchmarkRow>> _benchmarkConfigMetadataCache({
  required int iterations,
}) async {
  final config = _sampleConfig();
  final repository = _BenchmarkConfigRepository(
    delay: const Duration(microseconds: 80),
    config: config,
  );
  final cache = ActiveConfigMetadataCache(legacyRepository: repository);

  final coldSamples = <int>[];
  for (var i = 0; i < iterations; i++) {
    cache.invalidate();
    final stopwatch = Stopwatch()..start();
    await cache.resolveMetadata();
    stopwatch.stop();
    coldSamples.add(stopwatch.elapsedMicroseconds);
  }

  cache.invalidate();
  await cache.resolveMetadata();
  final warmSamples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    await cache.resolveMetadata();
    stopwatch.stop();
    warmSamples.add(stopwatch.elapsedMicroseconds);
  }

  final coldMedian = _median(coldSamples);
  final warmMedian = _median(warmSamples);

  return [
    PlugAgenteStackBenchmarkRow(
      scenario: 'config_metadata_cache',
      variant: 'cold',
      iterations: iterations,
      medianUs: coldMedian,
      p95Us: _p95(coldSamples),
      notes: 'repo_calls=${repository.metadataCallCount}',
    ),
    PlugAgenteStackBenchmarkRow(
      scenario: 'config_metadata_cache',
      variant: 'warm',
      iterations: iterations,
      medianUs: warmMedian,
      p95Us: _p95(warmSamples),
      speedup: coldMedian <= 0 ? null : coldMedian / max(warmMedian, 1),
      notes: 'repo_calls=${repository.metadataCallCount}',
    ),
  ];
}

List<PlugAgenteStackBenchmarkRow> _benchmarkConnectionStringTtlCache({
  required int iterations,
}) {
  final cache = OdbcConnectionStringTtlCache();
  var computeCount = 0;

  String compute() {
    computeCount++;
    final buffer = StringBuffer(
      'DRIVER={ODBC Driver 18 for SQL Server};SERVER=bench;DATABASE=db;UID=sa;PWD=secret',
    );
    for (var i = 0; i < 32; i++) {
      buffer.write(';OPT$i=$i');
    }
    return buffer.toString();
  }

  final coldSamples = <int>[];
  for (var i = 0; i < iterations; i++) {
    cache.invalidate();
    final stopwatch = Stopwatch()..start();
    cache.resolve(cacheKey: 'active', compute: compute);
    stopwatch.stop();
    coldSamples.add(stopwatch.elapsedMicroseconds);
  }

  cache.invalidate();
  cache.resolve(cacheKey: 'active', compute: compute);
  final warmSamples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    cache.resolve(cacheKey: 'active', compute: compute);
    stopwatch.stop();
    warmSamples.add(stopwatch.elapsedMicroseconds);
  }

  final coldMedian = _median(coldSamples);
  final warmMedian = _median(warmSamples);

  return [
    PlugAgenteStackBenchmarkRow(
      scenario: 'odbc_connection_string_ttl_cache',
      variant: 'cold',
      iterations: iterations,
      medianUs: coldMedian,
      p95Us: _p95(coldSamples),
      notes: 'compute_calls=$computeCount',
    ),
    PlugAgenteStackBenchmarkRow(
      scenario: 'odbc_connection_string_ttl_cache',
      variant: 'warm',
      iterations: iterations,
      medianUs: warmMedian,
      p95Us: _p95(warmSamples),
      speedup: coldMedian <= 0 ? null : coldMedian / max(warmMedian, 1),
      notes: 'compute_calls=$computeCount',
    ),
  ];
}

Future<List<PlugAgenteStackBenchmarkRow>> _benchmarkColumnarEmitter({
  required int rowCount,
  required int iterations,
}) async {
  final result = _largeTypedColumnarResult(rowCount);

  Future<int> measureRowMapPath() async {
    final samples = <int>[];
    for (var i = 0; i < iterations; i++) {
      var emittedRows = 0;
      final stopwatch = Stopwatch()..start();
      await OdbcColumnarStreamChunkEmitter.emit(
        result: result,
        fetchSize: 250,
        onChunk: (chunk) async {
          emittedRows += chunk.length;
        },
      );
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
      if (emittedRows != rowCount) {
        throw StateError('row-map path emitted $emittedRows rows, expected $rowCount');
      }
    }
    return _median(samples);
  }

  Future<int> measureWireOnlyPath() async {
    final samples = <int>[];
    for (var i = 0; i < iterations; i++) {
      final stopwatch = Stopwatch()..start();
      await OdbcColumnarStreamChunkEmitter.emit(
        result: result,
        fetchSize: 250,
        onChunk: (_) async {},
        onWireChunk: (_) async {},
        includeColumnarWire: true,
        wireOnly: true,
      );
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    return _median(samples);
  }

  final rowMapMedian = await measureRowMapPath();
  final wireOnlyMedian = await measureWireOnlyPath();
  final speedup = wireOnlyMedian <= 0 ? null : rowMapMedian / wireOnlyMedian;

  return [
    PlugAgenteStackBenchmarkRow(
      scenario: 'columnar_stream_emitter',
      variant: 'row_map',
      iterations: iterations,
      medianUs: rowMapMedian,
      rowsPerSec: rowCount / (rowMapMedian / 1e6),
      notes: 'rows=$rowCount',
    ),
    PlugAgenteStackBenchmarkRow(
      scenario: 'columnar_stream_emitter',
      variant: 'wire_only',
      iterations: iterations,
      medianUs: wireOnlyMedian,
      speedup: speedup,
      rowsPerSec: rowCount / (wireOnlyMedian / 1e6),
      notes: 'rows=$rowCount',
    ),
  ];
}

Future<List<PlugAgenteStackBenchmarkRow>> _benchmarkBackpressureEmitter({
  required int chunkCount,
  required int emitDelayUs,
}) async {
  Future<int> measureSequentialAdmission() async {
    final emitted = <int>[];
    final emitter = BackpressureStreamEmitter(
      emit: (event, payload) async {
        await Future<void>.delayed(Duration(microseconds: emitDelayUs));
        if (event == 'rpc:chunk') {
          emitted.add(payload['chunk_index'] as int);
        }
        return true;
      },
      onRegister: (_, _) => true,
      onUnregister: (_) {},
      initialSendCredit: 1,
    );

    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < chunkCount; index++) {
      await emitter.emitChunk(_sampleRpcChunk(index));
      if (index < chunkCount - 1) {
        emitter.releaseChunks(1);
      }
    }
    await emitter.emitComplete(
      RpcStreamComplete(streamId: 'bench', requestId: 'req', totalRows: chunkCount),
    );
    stopwatch.stop();
    if (emitted.length != chunkCount) {
      throw StateError('sequential path emitted ${emitted.length}/$chunkCount chunks');
    }
    return stopwatch.elapsedMicroseconds;
  }

  Future<int> measureConcurrentAdmission() async {
    final emitted = <int>[];
    final emitter = BackpressureStreamEmitter(
      emit: (event, payload) async {
        await Future<void>.delayed(Duration(microseconds: emitDelayUs));
        if (event == 'rpc:chunk') {
          emitted.add(payload['chunk_index'] as int);
        }
        return true;
      },
      onRegister: (_, _) => true,
      onUnregister: (_) {},
      initialSendCredit: 1,
    );

    final stopwatch = Stopwatch()..start();
    final pending = <Future<bool>>[];
    for (var index = 0; index < chunkCount; index++) {
      pending.add(emitter.emitChunk(_sampleRpcChunk(index)));
      emitter.releaseChunks(1);
    }
    await Future.wait(pending);
    await emitter.emitComplete(
      RpcStreamComplete(streamId: 'bench', requestId: 'req', totalRows: chunkCount),
    );
    stopwatch.stop();
    if (emitted.length != chunkCount) {
      throw StateError('concurrent path emitted ${emitted.length}/$chunkCount chunks');
    }
    return stopwatch.elapsedMicroseconds;
  }

  const runs = 5;
  final sequentialSamples = <int>[];
  final concurrentSamples = <int>[];
  for (var i = 0; i < runs; i++) {
    sequentialSamples.add(await measureSequentialAdmission());
    concurrentSamples.add(await measureConcurrentAdmission());
  }

  final sequentialMedian = _median(sequentialSamples);
  final concurrentMedian = _median(concurrentSamples);

  return [
    PlugAgenteStackBenchmarkRow(
      scenario: 'backpressure_stream_emitter',
      variant: 'sequential_admission',
      iterations: chunkCount * runs,
      medianUs: sequentialMedian,
      notes: 'chunks=$chunkCount emit_delay_us=$emitDelayUs',
    ),
    PlugAgenteStackBenchmarkRow(
      scenario: 'backpressure_stream_emitter',
      variant: 'concurrent_admission',
      iterations: chunkCount * runs,
      medianUs: concurrentMedian,
      speedup: concurrentMedian <= 0 ? null : sequentialMedian / concurrentMedian,
      notes: 'chunks=$chunkCount emit_delay_us=$emitDelayUs',
    ),
  ];
}

Future<List<PlugAgenteStackBenchmarkRow>> _benchmarkQueuedDatabaseGateway({
  required int iterations,
}) async {
  final delegate = _BenchmarkDatabaseGateway();
  final queue = SqlExecutionQueue(maxQueueSize: 64, maxConcurrentWorkers: 8);
  final gateway = QueuedDatabaseGateway(delegate: delegate, queue: queue);
  final request = QueryRequest(
    id: 'bench-req',
    agentId: 'agent-1',
    query: 'SELECT 1',
    timestamp: DateTime.utc(2026, 6, 16),
  );

  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    final result = await gateway.executeQuery(request);
    stopwatch.stop();
    if (result.isError()) {
      throw StateError('queued gateway failed: ${result.exceptionOrNull()}');
    }
    samples.add(stopwatch.elapsedMicroseconds);
  }

  return [
    PlugAgenteStackBenchmarkRow(
      scenario: 'queued_database_gateway',
      variant: 'execute_query',
      iterations: iterations,
      medianUs: _median(samples),
      p95Us: _p95(samples),
      notes: 'delegate_calls=${delegate.executeQueryCallCount}',
    ),
  ];
}

RpcStreamChunk _sampleRpcChunk(int index) {
  return RpcStreamChunk(
    streamId: 'bench',
    requestId: 'req',
    chunkIndex: index,
    rows: [
      {'id': index},
    ],
  );
}

TypedColumnarResult _largeTypedColumnarResult(int rowCount) {
  final rows = List<List<Object?>>.generate(
    rowCount,
    (index) => [index, 'name-$index', index.isEven, index * 1.5],
  );
  return toTypedColumnar(
    QueryResult(
      columns: const ['id', 'name', 'active', 'amount'],
      rows: rows,
      rowCount: rowCount,
    ),
  );
}

Config _sampleConfig() {
  final now = DateTime.utc(2026, 6, 16);
  return Config(
    id: 'cfg-bench',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 18 for SQL Server',
    connectionString: 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=bench;DATABASE=db',
    username: 'sa',
    databaseName: 'db',
    host: 'bench',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );
}

int _median(List<int> samples) {
  if (samples.isEmpty) {
    return 0;
  }
  final sorted = List<int>.from(samples)..sort();
  return sorted[sorted.length ~/ 2];
}

int _p95(List<int> samples) {
  if (samples.isEmpty) {
    return 0;
  }
  final sorted = List<int>.from(samples)..sort();
  final index = ((sorted.length - 1) * 0.95).round();
  return sorted[index];
}

class _BenchmarkConfigRepository implements IAgentConfigRepository {
  _BenchmarkConfigRepository({required this.delay, required this.config});

  final Duration delay;
  final Config config;
  int metadataCallCount = 0;

  @override
  Future<Result<Config>> getCurrentConfigMetadata() async {
    metadataCallCount++;
    await Future<void>.delayed(delay);
    return Success(config);
  }

  @override
  Future<Result<Config>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<Config>> getByIdMetadata(String id) => throw UnimplementedError();

  @override
  Future<Result<List<Config>>> getAll() => throw UnimplementedError();

  @override
  Future<Result<List<Config>>> getAllMetadata() => throw UnimplementedError();

  @override
  Future<Result<Config>> save(Config config) => throw UnimplementedError();

  @override
  Future<Result<void>> delete(String id) => throw UnimplementedError();

  @override
  Future<Result<Config>> getCurrentConfig() => throw UnimplementedError();
}

class _BenchmarkDatabaseGateway implements IDatabaseGateway {
  int executeQueryCallCount = 0;

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
  }) async {
    executeQueryCallCount++;
    return Success(
      QueryResponse(
        id: 'resp-${request.id}',
        requestId: request.id,
        agentId: request.agentId,
        data: const [
          {'col': 1},
        ],
        timestamp: DateTime.utc(2026, 6, 16),
      ),
    );
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) => throw UnimplementedError();

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) => throw UnimplementedError();

  @override
  Future<Result<int>> executeBulkInsert(
    BulkInsertRequest request, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) => throw UnimplementedError();
}

Future<void> main(List<String> args) async {
  final jsonOutput = args.contains('--json');
  final rows = await buildPlugAgenteStackBenchmarkRows();
  if (jsonOutput) {
    // ignore: avoid_print
    print(jsonEncode(buildPlugAgenteStackBenchmarkJson(rows: rows)));
    return;
  }
  // ignore: avoid_print
  print(await buildPlugAgenteStackBenchmarkReport());
}
