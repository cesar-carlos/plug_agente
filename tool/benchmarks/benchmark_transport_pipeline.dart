// ignore_for_file: unreachable_from_main

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart' show defaultTransportMaxInflationRatio;
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

import 'benchmark_transport_pipeline_async_stub.dart'
    if (dart.library.ui) 'benchmark_transport_pipeline_async_impl.dart';

const int defaultTransportCompressionThresholdBytes = 4096;

const String _usage = '''
Transport pipeline benchmark (sync and async codec paths).

The async path exercises TransportPipeline.prepareSendAsync and
receiveProcessAsync, including isolate offload for large JSON and GZIP.
Async mode requires Flutter (dart:ui); under plain `dart run` use --path sync
or run `flutter test test/infrastructure/codecs/transport_pipeline_benchmark_test.dart --tags perf`.
Use --gzip-isolate-threshold-sweep to compare isolate thresholds on the async path.

Usage:
  dart run tool/benchmarks/benchmark_transport_pipeline.dart [options]

Options:
  --iterations <n>                 Benchmark iterations per case (default: 20)
  --threshold <bytes>              compressionThreshold for gzip/auto (default: 4096)
  --path sync|async                Codec path (default: async)
  --gzip-isolate-threshold <bytes> GZIP isolate threshold for async path (default: 32768
                                   or TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES)
  --gzip-isolate-threshold-sweep <bytes,bytes,...>
                                   Run async path once per threshold (comma-separated)
  --json                           Emit JSON instead of plain text
  --help                           Show this help
''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage.trim());
    return;
  }

  final iterations = _readIntArg(args, '--iterations', 20).clamp(1, 10000);
  final threshold = _readIntArg(
    args,
    '--threshold',
    defaultTransportCompressionThresholdBytes,
  ).clamp(0, 1024 * 1024 * 1024);
  final path = _readStringArg(args, '--path', 'async');
  if (path != 'sync' && path != 'async') {
    stderr.writeln('Invalid --path value: $path (expected sync or async)');
    exitCode = 64;
    return;
  }
  final gzipIsolateThreshold = _readIntArg(
    args,
    '--gzip-isolate-threshold',
    ConnectionConstants.gzipIsolateThresholdBytes,
  ).clamp(1, 1024 * 1024 * 1024);
  final sweepThresholds = _readIntListArg(args, '--gzip-isolate-threshold-sweep');
  final jsonOutput = args.contains('--json');

  if (sweepThresholds.isNotEmpty && path != 'async') {
    stderr.writeln('--gzip-isolate-threshold-sweep requires --path async');
    exitCode = 64;
    return;
  }

  if (sweepThresholds.isNotEmpty) {
    final sweepReports = <Map<String, dynamic>>[];
    for (final sweepThreshold in sweepThresholds) {
      final results = await _buildBenchmarkResults(
        iterations: iterations,
        threshold: threshold,
        path: 'async',
        gzipIsolateThresholdBytes: sweepThreshold,
      );
      sweepReports.add(<String, dynamic>{
        'gzip_isolate_threshold_bytes': sweepThreshold,
        'results': results,
      });
    }

    if (jsonOutput) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'iterations': iterations,
          'threshold_bytes': threshold,
          'path': 'async',
          'sweep': sweepReports,
        }),
      );
      return;
    }

    stdout.writeln(
      _buildThresholdSweepReport(
        sweepReports,
        iterations: iterations,
        threshold: threshold,
      ),
    );
    return;
  }

  final results = await _buildBenchmarkResults(
    iterations: iterations,
    threshold: threshold,
    path: path,
    gzipIsolateThresholdBytes: gzipIsolateThreshold,
  );

  if (jsonOutput) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'iterations': iterations,
        'threshold_bytes': threshold,
        'path': path,
        'gzip_isolate_threshold_bytes': gzipIsolateThreshold,
        'results': results,
      }),
    );
    return;
  }

  stdout.writeln(
    _buildPlainTextReport(
      results,
      iterations: iterations,
      threshold: threshold,
      path: path,
      gzipIsolateThresholdBytes: gzipIsolateThreshold,
    ),
  );
}

Future<String> buildTransportPipelineBenchmarkReport({
  int iterations = 20,
  int warmupIterations = 1,
  int threshold = defaultTransportCompressionThresholdBytes,
  int? gzipIsolateThresholdBytes,
  String path = 'async',
}) async {
  final effectiveGzipIsolateThreshold = gzipIsolateThresholdBytes ?? ConnectionConstants.gzipIsolateThresholdBytes;
  await _buildBenchmarkResults(
    iterations: warmupIterations.clamp(0, 1000),
    threshold: threshold,
    path: path,
    gzipIsolateThresholdBytes: effectiveGzipIsolateThreshold,
  );
  final results = await _buildBenchmarkResults(
    iterations: iterations.clamp(1, 10000),
    threshold: threshold,
    path: path,
    gzipIsolateThresholdBytes: effectiveGzipIsolateThreshold,
  );
  final buffer = StringBuffer()
    ..writeln('# Transport Pipeline Benchmark')
    ..writeln()
    ..writeln('- iterations: $iterations')
    ..writeln('- warmupIterations: $warmupIterations')
    ..writeln('- thresholdBytes: $threshold')
    ..writeln('- path: $path')
    ..writeln('- gzipIsolateThresholdBytes: $effectiveGzipIsolateThreshold')
    ..writeln('- maxInflationRatio: $defaultTransportMaxInflationRatio')
    ..writeln('- stage-p50/p95/p99 (ms)')
    ..writeln()
    ..writeln(
      '| case | path | mode | signed | cmp | original | wire | saved | send p50/p95/p99 | receive p50/p95/p99 | isolates |',
    )
    ..writeln('| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final result in results) {
    buffer.writeln(
      '| ${result['case']} | $path | ${result['requested_compression']} | ${result['signed']} | '
      '${result['effective_compression']} | '
      '${_formatBytes(result['original_bytes'] as int)} | ${_formatBytes(result['wire_bytes'] as int)} | '
      '${_formatBytes(result['bytes_saved'] as int)} | '
      '${_formatMicrosTriple(result, 'send')} | ${_formatMicrosTriple(result, 'receive')} | '
      '${result['isolate_operations']} |',
    );
  }
  return buffer.toString();
}

Future<String> buildGzipIsolateThresholdSweepReport({
  int iterations = 20,
  int warmupIterations = 1,
  int threshold = defaultTransportCompressionThresholdBytes,
  List<int> sweepThresholds = const <int>[16 * 1024, 32 * 1024, 64 * 1024],
}) async {
  final sweepReports = <Map<String, dynamic>>[];
  for (final sweepThreshold in sweepThresholds) {
    await _buildBenchmarkResults(
      iterations: warmupIterations.clamp(0, 1000),
      threshold: threshold,
      path: 'async',
      gzipIsolateThresholdBytes: sweepThreshold,
    );
    final results = await _buildBenchmarkResults(
      iterations: iterations.clamp(1, 10000),
      threshold: threshold,
      path: 'async',
      gzipIsolateThresholdBytes: sweepThreshold,
    );
    sweepReports.add(<String, dynamic>{
      'gzip_isolate_threshold_bytes': sweepThreshold,
      'results': results,
    });
  }
  return _buildThresholdSweepReport(
    sweepReports,
    iterations: iterations,
    threshold: threshold,
  );
}

Future<List<Map<String, dynamic>>> _buildBenchmarkResults({
  required int iterations,
  required int threshold,
  required String path,
  required int gzipIsolateThresholdBytes,
}) async {
  if (iterations <= 0) {
    return const <Map<String, dynamic>>[];
  }
  final cases = <_BenchmarkCase>[
    _BenchmarkCase(name: 'small_sql_repetitive', payload: _buildSqlResponsePayload(rowCount: 25, columnCount: 6)),
    _BenchmarkCase(
      name: 'large_sql_low_compressibility',
      payload: _buildSqlResponsePayload(rowCount: 2500, columnCount: 8),
    ),
    _BenchmarkCase(
      name: 'large_incompressible_blob',
      payload: _buildIncompressibleBlobPayload(byteCount: 512 * 1024),
    ),
  ];
  final modes = <String>['none', 'auto', 'gzip'];
  final signedModes = <bool>[false, true];
  final results = <Map<String, dynamic>>[];

  for (final benchmarkCase in cases) {
    for (final mode in modes) {
      for (final signed in signedModes) {
        final result = path == 'async'
            ? await _runCaseAsync(
                benchmarkCase: benchmarkCase,
                compressionMode: mode,
                signed: signed,
                iterations: iterations,
                threshold: threshold,
                gzipIsolateThresholdBytes: gzipIsolateThresholdBytes,
              )
            : await _runCaseSync(
                benchmarkCase: benchmarkCase,
                compressionMode: mode,
                signed: signed,
                iterations: iterations,
                threshold: threshold,
              );
        results.add(result);
      }
    }
  }
  return results;
}

Future<Map<String, dynamic>> _runCaseAsync({
  required _BenchmarkCase benchmarkCase,
  required String compressionMode,
  required bool signed,
  required int iterations,
  required int threshold,
  required int gzipIsolateThresholdBytes,
}) {
  return runTransportPipelineBenchmarkCaseAsync(
    payload: benchmarkCase.payload,
    benchmarkCaseName: benchmarkCase.name,
    compressionMode: compressionMode,
    signed: signed,
    iterations: iterations,
    threshold: threshold,
    gzipIsolateThresholdBytes: gzipIsolateThresholdBytes,
  );
}

Future<Map<String, dynamic>> _runCaseSync({
  required _BenchmarkCase benchmarkCase,
  required String compressionMode,
  required bool signed,
  required int iterations,
  required int threshold,
}) async {
  final collector = ProtocolMetricsCollector(maxEntries: iterations * 2 + 4);
  final signer = signed
      ? PayloadSigner(
          keys: const <String, String>{'benchmark': 'benchmark-secret'},
          activeKeyId: 'benchmark',
        )
      : null;
  for (var i = 0; i < iterations; i++) {
    final frame = _prepareFrameSync(
      payload: benchmarkCase.payload,
      compressionMode: compressionMode,
      signer: signer,
      threshold: threshold,
      metricEventName: benchmarkCase.name,
      collector: collector,
    );
    _receiveFrameSync(
      frame: frame,
      requestedCompression: compressionMode,
      metricEventName: benchmarkCase.name,
      collector: collector,
    );
  }

  return _buildCaseResult(
    benchmarkCase: benchmarkCase,
    compressionMode: compressionMode,
    signed: signed,
    iterations: iterations,
    collector: collector,
  );
}

Map<String, dynamic> _buildCaseResult({
  required _BenchmarkCase benchmarkCase,
  required String compressionMode,
  required bool signed,
  required int iterations,
  required ProtocolMetricsCollector collector,
}) {
  final summary = collector.getSummary();
  final sendSummary = ProtocolMetricsSummaryBuilder.fromList(
    collector.metrics.where((metric) => metric.direction == 'send').toList(growable: false),
  );
  final receiveSummary = ProtocolMetricsSummaryBuilder.fromList(
    collector.metrics.where((metric) => metric.direction == 'receive').toList(growable: false),
  );
  final sendMetric = collector.metrics.firstWhere((metric) => metric.direction == 'send');
  collector.dispose();

  return <String, dynamic>{
    'case': benchmarkCase.name,
    'requested_compression': compressionMode,
    'signed': signed,
    'effective_compression': sendMetric.compression,
    'iterations': iterations,
    'original_bytes': sendMetric.originalSize,
    'wire_bytes': sendMetric.compressedSize,
    'bytes_saved': sendMetric.bytesSaved,
    'compression_efficiency': sendMetric.originalSize == 0 ? 0 : sendMetric.bytesSaved / sendMetric.originalSize,
    'send_p50_us': sendSummary.totalDurationPercentiles.p50Us,
    'send_p95_us': sendSummary.totalDurationPercentiles.p95Us,
    'send_p99_us': sendSummary.totalDurationPercentiles.p99Us,
    'receive_p50_us': receiveSummary.totalDurationPercentiles.p50Us,
    'receive_p95_us': receiveSummary.totalDurationPercentiles.p95Us,
    'receive_p99_us': receiveSummary.totalDurationPercentiles.p99Us,
    'isolate_operations': summary.totalIsolateOperations,
    'json_encode_isolate_operations': summary.jsonEncodeIsolateOperations,
    'gzip_compress_isolate_operations': summary.gzipCompressIsolateOperations,
    'json_decode_isolate_operations': summary.jsonDecodeIsolateOperations,
    'gzip_decompress_isolate_operations': summary.gzipDecompressIsolateOperations,
    'summary': summary.toJson(),
  };
}

PayloadFrame _prepareFrameSync({
  required Map<String, dynamic> payload,
  required String compressionMode,
  required PayloadSigner? signer,
  required int threshold,
  required String metricEventName,
  required ProtocolMetricsCollector collector,
}) {
  final totalStopwatch = Stopwatch()..start();
  final encodeStopwatch = Stopwatch()..start();
  final codec = PayloadCodecFactory.getCodec('json');
  final encodedBytes = codec.encode(payload).getOrThrow();
  encodeStopwatch.stop();

  final originalSize = encodedBytes.length;
  final shouldCompress = compressionMode != 'none' && originalSize >= threshold;
  var finalBytes = encodedBytes;
  var finalCompression = 'none';
  int? compressDurationUs;

  if (shouldCompress) {
    final compressStopwatch = Stopwatch()..start();
    final compressedBytes = CompressionCodecFactory.getCodec('gzip').compress(encodedBytes).getOrThrow();
    compressStopwatch.stop();
    compressDurationUs = compressStopwatch.elapsedMicroseconds;
    final withinInflationGuard =
        compressedBytes.isNotEmpty && encodedBytes.length / compressedBytes.length <= defaultTransportMaxInflationRatio;
    final shouldUseCompressed =
        withinInflationGuard && (compressionMode != 'auto' || compressedBytes.length < encodedBytes.length);
    if (shouldUseCompressed) {
      finalBytes = compressedBytes;
      finalCompression = 'gzip';
    }
  }

  int? signDurationUs;
  var frame = PayloadFrame(
    schemaVersion: '1.0',
    enc: 'json',
    cmp: finalCompression,
    contentType: codec.contentType,
    originalSize: originalSize,
    compressedSize: finalBytes.length,
    payload: finalBytes,
    traceId: 'benchmark',
  );
  if (signer != null) {
    final signStopwatch = Stopwatch()..start();
    frame = frame.copyWith(signature: signer.signFrame(frame).toJson());
    signStopwatch.stop();
    signDurationUs = signStopwatch.elapsedMicroseconds;
  }
  totalStopwatch.stop();
  collector.record(
    ProtocolMetrics(
      timestamp: DateTime.now().toUtc(),
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: finalCompression,
      requestedCompression: compressionMode,
      originalSize: originalSize,
      compressedSize: finalBytes.length,
      direction: 'send',
      eventName: metricEventName,
      totalDurationUs: totalStopwatch.elapsedMicroseconds,
      encodeDurationUs: encodeStopwatch.elapsedMicroseconds,
      compressDurationUs: compressDurationUs,
      signDurationUs: signDurationUs,
    ),
  );

  return frame;
}

void _receiveFrameSync({
  required PayloadFrame frame,
  required String requestedCompression,
  required String metricEventName,
  required ProtocolMetricsCollector collector,
}) {
  final totalStopwatch = Stopwatch()..start();
  final bytes = frame.payload is Uint8List
      ? frame.payload as Uint8List
      : Uint8List.fromList(frame.payload as List<int>);
  var decodableBytes = bytes;
  int? decompressDurationUs;

  if (frame.cmp == 'gzip') {
    final decompressStopwatch = Stopwatch()..start();
    decodableBytes = CompressionCodecFactory.getCodec('gzip').decompress(bytes).getOrThrow();
    decompressStopwatch.stop();
    decompressDurationUs = decompressStopwatch.elapsedMicroseconds;
    if (bytes.isNotEmpty && decodableBytes.length / bytes.length > defaultTransportMaxInflationRatio) {
      throw StateError('Benchmark frame exceeds maxInflationRatio');
    }
  }

  final decodeStopwatch = Stopwatch()..start();
  PayloadCodecFactory.getCodec('json').decode(decodableBytes).getOrThrow();
  decodeStopwatch.stop();
  totalStopwatch.stop();

  collector.record(
    ProtocolMetrics(
      timestamp: DateTime.now().toUtc(),
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: frame.cmp,
      requestedCompression: requestedCompression,
      originalSize: frame.originalSize,
      compressedSize: frame.compressedSize,
      direction: 'receive',
      eventName: metricEventName,
      totalDurationUs: totalStopwatch.elapsedMicroseconds,
      decodeDurationUs: decodeStopwatch.elapsedMicroseconds,
      decompressDurationUs: decompressDurationUs,
    ),
  );
}

Map<String, dynamic> _buildSqlResponsePayload({
  required int rowCount,
  required int columnCount,
}) {
  final columns = <Map<String, dynamic>>[
    for (var i = 0; i < columnCount; i++)
      <String, dynamic>{
        'name': 'column_$i',
        'type': i.isEven ? 'varchar' : 'integer',
        'nullable': i % 3 == 0,
      },
  ];
  final rows = <Map<String, dynamic>>[
    for (var row = 0; row < rowCount; row++)
      <String, dynamic>{
        for (var col = 0; col < columnCount; col++)
          'column_$col': col.isEven ? 'value_${row}_$col repeated text for compression' : row * (col + 1),
      },
  ];

  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'benchmark-$rowCount',
    'result': <String, dynamic>{
      'execution_id': 'bench-$rowCount',
      'started_at': '2026-05-11T00:00:00.000Z',
      'finished_at': '2026-05-11T00:00:01.000Z',
      'column_metadata': columns,
      'rows': rows,
      'row_count': rows.length,
    },
  };
}

Map<String, dynamic> _buildIncompressibleBlobPayload({
  required int byteCount,
}) {
  var state = 0x6d2b79f5;
  final bytes = Uint8List(byteCount);
  for (var i = 0; i < bytes.length; i++) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    bytes[i] = state & 0xff;
  }

  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'benchmark-blob',
    'result': <String, dynamic>{
      'content_type': 'application/octet-stream',
      'encoding': 'base64',
      'blob': base64Encode(bytes),
    },
  };
}

int _readIntArg(List<String> args, String name, int fallback) {
  final inlinePrefix = '$name=';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith(inlinePrefix)) {
      return int.tryParse(arg.substring(inlinePrefix.length)) ?? fallback;
    }
    if (arg == name && i + 1 < args.length) {
      return int.tryParse(args[i + 1]) ?? fallback;
    }
  }
  return fallback;
}

String _readStringArg(List<String> args, String name, String fallback) {
  final inlinePrefix = '$name=';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith(inlinePrefix)) {
      return arg.substring(inlinePrefix.length);
    }
    if (arg == name && i + 1 < args.length) {
      return args[i + 1];
    }
  }
  return fallback;
}

List<int> _readIntListArg(List<String> args, String name) {
  final inlinePrefix = '$name=';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final raw = arg.startsWith(inlinePrefix)
        ? arg.substring(inlinePrefix.length)
        : arg == name && i + 1 < args.length
        ? args[i + 1]
        : null;
    if (raw == null) {
      continue;
    }
    return raw
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .where((value) => value > 0)
        .toList(growable: false);
  }
  return const <int>[];
}

String _formatBytes(int bytes) {
  if (bytes.abs() >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  if (bytes.abs() >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  return '${bytes}B';
}

String _formatMicros(int micros) {
  if (micros >= 1000) {
    return '${(micros / 1000).toStringAsFixed(1)}ms';
  }
  return '${micros}us';
}

String _formatMicrosTriple(Map<String, dynamic> result, String prefix) {
  return '${_formatMicros(result['${prefix}_p50_us'] as int)}/'
      '${_formatMicros(result['${prefix}_p95_us'] as int)}/'
      '${_formatMicros(result['${prefix}_p99_us'] as int)}';
}

String _buildPlainTextReport(
  List<Map<String, dynamic>> results, {
  required int iterations,
  required int threshold,
  required String path,
  required int gzipIsolateThresholdBytes,
}) {
  final buffer = StringBuffer()
    ..writeln('Transport pipeline benchmark')
    ..writeln(
      'iterations=$iterations threshold_bytes=$threshold path=$path '
      'gzip_isolate_threshold_bytes=$gzipIsolateThresholdBytes',
    )
    ..writeln()
    ..writeln(
      [
        'case'.padRight(30),
        'mode'.padRight(6),
        'signed'.padRight(6),
        'cmp'.padRight(5),
        'orig'.padLeft(10),
        'wire'.padLeft(10),
        'saved'.padLeft(10),
        'p95 send'.padLeft(10),
        'p95 recv'.padLeft(10),
        'isolates'.padLeft(8),
        'gz-c'.padLeft(6),
        'gz-d'.padLeft(6),
      ].join('  '),
    );
  for (final result in results) {
    buffer.writeln(
      [
        (result['case'] as String).padRight(30),
        (result['requested_compression'] as String).padRight(6),
        '${result['signed']}'.padRight(6),
        (result['effective_compression'] as String).padRight(5),
        _formatBytes(result['original_bytes'] as int).padLeft(10),
        _formatBytes(result['wire_bytes'] as int).padLeft(10),
        _formatBytes(result['bytes_saved'] as int).padLeft(10),
        _formatMicros(result['send_p95_us'] as int).padLeft(10),
        _formatMicros(result['receive_p95_us'] as int).padLeft(10),
        '${result['isolate_operations']}'.padLeft(8),
        '${result['gzip_compress_isolate_operations']}'.padLeft(6),
        '${result['gzip_decompress_isolate_operations']}'.padLeft(6),
      ].join('  '),
    );
  }
  return buffer.toString();
}

String _buildThresholdSweepReport(
  List<Map<String, dynamic>> sweepReports, {
  required int iterations,
  required int threshold,
}) {
  final buffer = StringBuffer()
    ..writeln('Transport pipeline gzip isolate threshold sweep (async path)')
    ..writeln('iterations=$iterations threshold_bytes=$threshold')
    ..writeln()
    ..writeln(
      [
        'threshold'.padRight(12),
        'case'.padRight(30),
        'mode'.padRight(6),
        'cmp'.padRight(5),
        'p95 send'.padLeft(10),
        'p95 recv'.padLeft(10),
        'isolates'.padLeft(8),
        'gz-c'.padLeft(6),
        'gz-d'.padLeft(6),
      ].join('  '),
    );

  for (final sweepEntry in sweepReports) {
    final sweepThreshold = sweepEntry['gzip_isolate_threshold_bytes'] as int;
    final results = sweepEntry['results'] as List<Map<String, dynamic>>;
    for (final result in results) {
      if (result['requested_compression'] != 'gzip' || result['signed'] != false) {
        continue;
      }
      buffer.writeln(
        [
          _formatBytes(sweepThreshold).padRight(12),
          (result['case'] as String).padRight(30),
          (result['requested_compression'] as String).padRight(6),
          (result['effective_compression'] as String).padRight(5),
          _formatMicros(result['send_p95_us'] as int).padLeft(10),
          _formatMicros(result['receive_p95_us'] as int).padLeft(10),
          '${result['isolate_operations']}'.padLeft(8),
          '${result['gzip_compress_isolate_operations']}'.padLeft(6),
          '${result['gzip_decompress_isolate_operations']}'.padLeft(6),
        ].join('  '),
      );
    }
  }
  return buffer.toString();
}

class _BenchmarkCase {
  const _BenchmarkCase({
    required this.name,
    required this.payload,
  });

  final String name;
  final Map<String, dynamic> payload;
}
