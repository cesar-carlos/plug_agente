import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';

const double _benchmarkMaxInflationRatio = 200;
const int _incompressibleBlobBytes = 256 * 1024;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final iterations = _parseIntArg(args, '--iterations') ?? 12;
  final warmupIterations = _parseIntArg(args, '--warmup') ?? 2;
  final report = await buildTransportPipelineBenchmarkReport(
    iterations: iterations,
    warmupIterations: warmupIterations,
  );
  stdout.writeln(report);
}

Future<String> buildTransportPipelineBenchmarkReport({
  int iterations = 12,
  int warmupIterations = 2,
}) async {
  final scenarios = <_BenchmarkScenario>[
    _BenchmarkScenario(
      name: 'small_sql_repetitive',
      payload: _buildSqlPayload(
        rowCount: 12,
        repeatedValues: true,
        seed: 11,
      ),
      iterations: iterations,
      warmupIterations: warmupIterations,
    ),
    _BenchmarkScenario(
      name: 'medium_sql_repetitive',
      payload: _buildSqlPayload(
        rowCount: 350,
        repeatedValues: true,
        seed: 21,
      ),
      iterations: iterations,
      warmupIterations: warmupIterations,
    ),
    _BenchmarkScenario(
      name: 'large_sql_repetitive',
      payload: _buildSqlPayload(
        rowCount: 2500,
        repeatedValues: true,
        seed: 31,
      ),
      iterations: max(6, iterations ~/ 2),
      warmupIterations: warmupIterations,
    ),
    _BenchmarkScenario(
      name: 'medium_sql_low_compressibility',
      payload: _buildSqlPayload(
        rowCount: 350,
        repeatedValues: false,
        seed: 41,
      ),
      iterations: iterations,
      warmupIterations: warmupIterations,
    ),
    _BenchmarkScenario(
      name: 'large_sql_low_compressibility',
      payload: _buildSqlPayload(
        rowCount: 2500,
        repeatedValues: false,
        seed: 51,
      ),
      iterations: max(6, iterations ~/ 2),
      warmupIterations: warmupIterations,
    ),
    _BenchmarkScenario(
      name: 'large_incompressible_blob',
      payload: _buildIncompressibleBlobPayload(
        bytesLength: _incompressibleBlobBytes,
        seed: 61,
      ),
      iterations: max(6, iterations ~/ 2),
      warmupIterations: warmupIterations,
    ),
  ];

  const executionModes = <_ExecutionMode>[
    _ExecutionMode(name: 'sync', useAsyncPipeline: false),
    _ExecutionMode(name: 'async', useAsyncPipeline: true),
  ];
  const compressionModes = <String>['none', 'gzip', 'auto'];
  final report = StringBuffer()
    ..writeln('# Transport Pipeline Benchmark')
    ..writeln()
    ..writeln('- iterations: $iterations')
    ..writeln('- warmup_iterations: $warmupIterations')
    ..writeln('- compression_threshold_bytes: 1024')
    ..writeln('- gzip_isolate_threshold_bytes: $gzipIsolateThresholdBytes')
    ..writeln(
      '- json_payload_isolate_threshold_bytes: '
      '$jsonPayloadIsolateEncodeThresholdBytes',
    )
    ..writeln('- benchmark_max_inflation_ratio: $_benchmarkMaxInflationRatio')
    ..writeln('- incompressible_blob_bytes: $_incompressibleBlobBytes')
    ..writeln();

  for (final scenario in scenarios) {
    report.writeln('## ${scenario.name}');
    report.writeln();
    report.writeln(
      '| path | requested_cmp | final_cmp | avg_original_bytes | '
      'avg_wire_bytes | avg_send_ms | avg_receive_ms | avg_roundtrip_ms | '
      'roundtrip_p95_ms | isolate_ops |',
    );
    report.writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');

    for (final execution in executionModes) {
      for (final compression in compressionModes) {
        final result = await _runScenario(
          scenario: scenario,
          executionMode: execution,
          compression: compression,
        );
        report.writeln(
          '| ${execution.name} | $compression | ${result.finalCompressionUsage} '
          '| ${result.averageOriginalBytes.toStringAsFixed(0)} '
          '| ${result.averageWireBytes.toStringAsFixed(0)} '
          '| ${result.averageSendMs.toStringAsFixed(3)} '
          '| ${result.averageReceiveMs.toStringAsFixed(3)} '
          '| ${result.averageRoundTripMs.toStringAsFixed(3)} '
          '| ${result.roundTripP95Ms.toStringAsFixed(3)} '
          '| ${result.isolateOperations} |',
        );
        report.writeln(
          '| stage-p50/p95/p99 (ms) | - | - | - | - | '
          '${result.sendTotalPercentiles.format()} | '
          '${result.receiveTotalPercentiles.format()} | '
          '${result.roundTripPercentiles.format()} | - | - |',
        );
        report.writeln(
          '| encode/compress/decode/decompress p95 (ms) | - | - | - | - | '
          '${result.encodeP95Ms.toStringAsFixed(3)} / ${result.compressP95Ms.toStringAsFixed(3)} '
          '| ${result.decodeP95Ms.toStringAsFixed(3)} / ${result.decompressP95Ms.toStringAsFixed(3)} '
          '| - | - | - |',
        );
      }
    }

    report.writeln();
  }

  return report.toString();
}

Future<_ScenarioResult> _runScenario({
  required _BenchmarkScenario scenario,
  required _ExecutionMode executionMode,
  required String compression,
}) async {
  final collector = ProtocolMetricsCollector();
  final pipeline = TransportPipeline(
    encoding: 'json',
    compression: compression,
    metricsCollector: collector,
  );
  final roundTripTimingsMs = <double>[];

  for (var i = 0; i < scenario.warmupIterations; i++) {
    await _runSingleIteration(
      pipeline: pipeline,
      payload: scenario.payload,
      useAsyncPipeline: executionMode.useAsyncPipeline,
    );
  }

  collector.clear();

  for (var i = 0; i < scenario.iterations; i++) {
    final stopwatch = Stopwatch()..start();
    await _runSingleIteration(
      pipeline: pipeline,
      payload: scenario.payload,
      useAsyncPipeline: executionMode.useAsyncPipeline,
    );
    stopwatch.stop();
    roundTripTimingsMs.add(stopwatch.elapsedMicroseconds / 1000);
  }

  final summary = collector.getSummary();
  final sendMetrics = collector.metrics.where((metric) => metric.direction == 'send').toList(growable: false);
  final receiveMetrics = collector.metrics.where((metric) => metric.direction == 'receive').toList(growable: false);
  final sendTotalMs = sendMetrics.map((metric) => (metric.totalDurationUs ?? 0) / 1000).toList(growable: false);
  final receiveTotalMs = receiveMetrics.map((metric) => (metric.totalDurationUs ?? 0) / 1000).toList(growable: false);
  final encodeMs = sendMetrics.map((metric) => (metric.encodeDurationUs ?? 0) / 1000).toList(growable: false);
  final compressMs = sendMetrics.map((metric) => (metric.compressDurationUs ?? 0) / 1000).toList(growable: false);
  final decodeMs = receiveMetrics.map((metric) => (metric.decodeDurationUs ?? 0) / 1000).toList(growable: false);
  final decompressMs = receiveMetrics
      .map((metric) => (metric.decompressDurationUs ?? 0) / 1000)
      .toList(growable: false);
  final roundTripPercentiles = _computePercentiles(roundTripTimingsMs);

  return _ScenarioResult(
    averageOriginalBytes: _average(sendMetrics.map((metric) => metric.originalSize.toDouble())),
    averageWireBytes: _average(sendMetrics.map((metric) => metric.compressedSize.toDouble())),
    averageSendMs: summary.averageTotalDurationUs == 0
        ? 0
        : _average(
            sendMetrics.map(
              (metric) => (metric.totalDurationUs ?? 0) / 1000,
            ),
          ),
    averageReceiveMs: _average(
      receiveMetrics.map((metric) => (metric.totalDurationUs ?? 0) / 1000),
    ),
    averageRoundTripMs: _average(roundTripTimingsMs),
    roundTripP95Ms: roundTripPercentiles.p95,
    sendTotalPercentiles: _computePercentiles(sendTotalMs),
    receiveTotalPercentiles: _computePercentiles(receiveTotalMs),
    roundTripPercentiles: roundTripPercentiles,
    encodeP95Ms: _computePercentiles(encodeMs).p95,
    compressP95Ms: _computePercentiles(compressMs).p95,
    decodeP95Ms: _computePercentiles(decodeMs).p95,
    decompressP95Ms: _computePercentiles(decompressMs).p95,
    finalCompressionUsage: _formatCounts(summary.compressionUsage),
    isolateOperations: summary.totalIsolateOperations,
  );
}

Future<void> _runSingleIteration({
  required TransportPipeline pipeline,
  required Map<String, dynamic> payload,
  required bool useAsyncPipeline,
}) async {
  if (useAsyncPipeline) {
    final frame = (await pipeline.prepareSendAsync(payload)).getOrThrow();
    (await pipeline.receiveProcessAsync(
      frame,
      maxInflationRatio: _benchmarkMaxInflationRatio,
    )).getOrThrow();
    return;
  }

  final frame = pipeline.prepareSend(payload).getOrThrow();
  pipeline
      .receiveProcess(
        frame,
        maxInflationRatio: _benchmarkMaxInflationRatio,
      )
      .getOrThrow();
}

Map<String, dynamic> _buildSqlPayload({
  required int rowCount,
  required bool repeatedValues,
  required int seed,
}) {
  final random = Random(seed);
  final rows = List<Map<String, dynamic>>.generate(rowCount, (index) {
    final city = repeatedValues ? 'Sao Paulo' : _randomToken(random, 24);
    final role = repeatedValues ? 'operator' : _randomToken(random, 18);
    final status = repeatedValues ? 'active' : _randomToken(random, 12);
    final notes = repeatedValues ? 'replicated_sql_payload_segment_${index % 8}' : _randomToken(random, 96);

    return <String, dynamic>{
      'customer_id': index,
      'tenant_id': repeatedValues ? 'tenant_a' : _randomToken(random, 12),
      'full_name': repeatedValues ? 'Maria Silva' : _randomToken(random, 28),
      'email': repeatedValues ? 'customer@example.com' : '${_randomToken(random, 10)}@example.com',
      'city': city,
      'role': role,
      'status': status,
      'notes': notes,
      'updated_at': repeatedValues ? '2026-04-03T12:00:00Z' : '2026-04-03T12:00:${index % 60}Z',
    };
  }, growable: false);

  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'bench-$seed-$rowCount',
    'result': <String, dynamic>{
      'execution_id': 'exec-$seed',
      'row_count': rowCount,
      'rows': rows,
      'column_metadata': const [
        {'name': 'customer_id', 'type': 'int'},
        {'name': 'tenant_id', 'type': 'varchar'},
        {'name': 'full_name', 'type': 'varchar'},
        {'name': 'email', 'type': 'varchar'},
        {'name': 'city', 'type': 'varchar'},
        {'name': 'role', 'type': 'varchar'},
        {'name': 'status', 'type': 'varchar'},
        {'name': 'notes', 'type': 'varchar'},
        {'name': 'updated_at', 'type': 'datetime'},
      ],
    },
    'meta': <String, dynamic>{
      'agent_id': 'agent-benchmark',
      'request_id': 'bench-$seed-$rowCount',
      'trace_id': 'trace-$seed',
      'timestamp': '2026-04-03T12:00:00Z',
    },
  };
}

Map<String, dynamic> _buildIncompressibleBlobPayload({
  required int bytesLength,
  required int seed,
}) {
  final bytes = Uint8List(bytesLength);
  final random = Random(seed);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  final blob = base64Encode(bytes);

  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'blob-$seed-$bytesLength',
    'result': <String, dynamic>{
      'execution_id': 'blob-$seed',
      'blob_base64': blob,
    },
    'meta': <String, dynamic>{
      'agent_id': 'agent-benchmark',
      'request_id': 'blob-$seed-$bytesLength',
      'trace_id': 'trace-blob-$seed',
      'timestamp': '2026-04-03T12:00:00Z',
    },
  };
}

String _randomToken(Random random, int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

String _formatCounts(Map<String, int> counts) {
  if (counts.isEmpty) {
    return 'n/a';
  }
  return counts.entries.map((entry) => '${entry.key}:${entry.value}').join(', ');
}

double _average(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value;
    count++;
  }
  if (count == 0) {
    return 0;
  }
  return sum / count;
}

_Percentiles _computePercentiles(List<double> values) {
  if (values.isEmpty) {
    return const _Percentiles.zero();
  }
  final sorted = values.toList()..sort();
  return _Percentiles(
    p50: _percentile(sorted, 0.50),
    p95: _percentile(sorted, 0.95),
    p99: _percentile(sorted, 0.99),
  );
}

double _percentile(List<double> sorted, double percentile) {
  if (sorted.isEmpty) {
    return 0;
  }
  final position = (sorted.length - 1) * percentile;
  final lowerIndex = position.floor();
  final upperIndex = position.ceil();
  if (lowerIndex == upperIndex) {
    return sorted[lowerIndex];
  }
  final lowerValue = sorted[lowerIndex];
  final upperValue = sorted[upperIndex];
  final ratio = position - lowerIndex;
  return lowerValue + (upperValue - lowerValue) * ratio;
}

int? _parseIntArg(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith('$prefix=')) {
      return int.tryParse(arg.substring(prefix.length + 1));
    }
  }
  return null;
}

class _BenchmarkScenario {
  const _BenchmarkScenario({
    required this.name,
    required this.payload,
    required this.iterations,
    required this.warmupIterations,
  });

  final String name;
  final Map<String, dynamic> payload;
  final int iterations;
  final int warmupIterations;
}

class _ExecutionMode {
  const _ExecutionMode({
    required this.name,
    required this.useAsyncPipeline,
  });

  final String name;
  final bool useAsyncPipeline;
}

class _ScenarioResult {
  const _ScenarioResult({
    required this.averageOriginalBytes,
    required this.averageWireBytes,
    required this.averageSendMs,
    required this.averageReceiveMs,
    required this.averageRoundTripMs,
    required this.roundTripP95Ms,
    required this.sendTotalPercentiles,
    required this.receiveTotalPercentiles,
    required this.roundTripPercentiles,
    required this.encodeP95Ms,
    required this.compressP95Ms,
    required this.decodeP95Ms,
    required this.decompressP95Ms,
    required this.finalCompressionUsage,
    required this.isolateOperations,
  });

  final double averageOriginalBytes;
  final double averageWireBytes;
  final double averageSendMs;
  final double averageReceiveMs;
  final double averageRoundTripMs;
  final double roundTripP95Ms;
  final _Percentiles sendTotalPercentiles;
  final _Percentiles receiveTotalPercentiles;
  final _Percentiles roundTripPercentiles;
  final double encodeP95Ms;
  final double compressP95Ms;
  final double decodeP95Ms;
  final double decompressP95Ms;
  final String finalCompressionUsage;
  final int isolateOperations;
}

class _Percentiles {
  const _Percentiles({
    required this.p50,
    required this.p95,
    required this.p99,
  });

  const _Percentiles.zero() : p50 = 0, p95 = 0, p99 = 0;

  final double p50;
  final double p95;
  final double p99;

  String format() => '${p50.toStringAsFixed(3)} / ${p95.toStringAsFixed(3)} / ${p99.toStringAsFixed(3)}';
}
