@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:uuid/uuid.dart';

import '../../../tool/e2e_benchmark_summary.dart';
import '../../helpers/e2e_benchmark_assertions.dart';
import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

const String _caseSmallRoundTrip = 'socket_transport_small_roundtrip';
const String _caseLargeGzipRoundTrip = 'socket_transport_large_roundtrip_gzip';
const String _caseLargeAutoRoundTrip = 'socket_transport_large_roundtrip_auto';
const String _caseStreamChunksGzip = 'socket_transport_stream_chunks_gzip';
const String _caseJumboGzipAsync = 'socket_transport_jumbo_gzip_roundtrip_async';

class _TransportIterationMeasurement {
  const _TransportIterationMeasurement({
    required this.originalBytes,
    required this.compressedBytes,
    required this.frameCount,
    required this.encodeLatencyMs,
    required this.decodeLatencyMs,
    required this.sendLatencyMs,
  });

  final int originalBytes;
  final int compressedBytes;
  final int frameCount;
  final int encodeLatencyMs;
  final int decodeLatencyMs;
  final int sendLatencyMs;
}

class _TransportCaseMeasurement {
  const _TransportCaseMeasurement({
    required this.stats,
    required this.originalBytesSamples,
    required this.compressedBytesSamples,
    required this.frameCountSamples,
    required this.encodeLatencySamplesMs,
    required this.decodeLatencySamplesMs,
    required this.sendLatencySamplesMs,
  });

  final E2eBenchmarkStats stats;
  final List<int> originalBytesSamples;
  final List<int> compressedBytesSamples;
  final List<int> frameCountSamples;
  final List<int> encodeLatencySamplesMs;
  final List<int> decodeLatencySamplesMs;
  final List<int> sendLatencySamplesMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...stats.toJson(),
      'original_bytes_median': _medianInt(originalBytesSamples),
      'original_bytes_samples': List<int>.from(originalBytesSamples),
      'compressed_bytes_median': _medianInt(compressedBytesSamples),
      'compressed_bytes_samples': List<int>.from(compressedBytesSamples),
      'frame_count_median': _medianInt(frameCountSamples),
      'frame_count_samples': List<int>.from(frameCountSamples),
      'stage_encode_p95_ms': _p95Int(encodeLatencySamplesMs),
      'stage_encode_samples_ms': List<int>.from(encodeLatencySamplesMs),
      'stage_decode_p95_ms': _p95Int(decodeLatencySamplesMs),
      'stage_decode_samples_ms': List<int>.from(decodeLatencySamplesMs),
      'stage_send_p95_ms': _p95Int(sendLatencySamplesMs),
      'stage_send_samples_ms': List<int>.from(sendLatencySamplesMs),
    };
  }
}

int _medianInt(List<int> samples) {
  if (samples.isEmpty) {
    return 0;
  }
  final sorted = List<int>.from(samples)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

int _p95Int(List<int> samples) {
  if (samples.isEmpty) {
    return 0;
  }
  final sorted = List<int>.from(samples)..sort();
  final idx = ((sorted.length * 0.95).ceil() - 1).clamp(0, sorted.length - 1);
  return sorted[idx];
}

bool _envFlag(String key) => E2EEnv.get(key) == 'true';

int _positiveIntEnv(String key, int fallback) {
  final raw = E2EEnv.get(key);
  final parsed = int.tryParse(raw ?? '');
  if (parsed == null || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

double? _nonNegativeDoubleEnv(String key) {
  final raw = E2EEnv.get(key);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = double.tryParse(raw);
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

String _transportBenchmarkFile() {
  final raw = E2EEnv.get('SOCKET_TRANSPORT_BENCHMARK_FILE')?.trim();
  if (raw != null && raw.isNotEmpty) {
    return raw;
  }
  return 'benchmark${Platform.pathSeparator}socket_transport.jsonl';
}

String? _transportBenchmarkBaselineFile() {
  final raw = E2EEnv.get('SOCKET_TRANSPORT_BENCHMARK_BASELINE_FILE')?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
}

int _transportBenchmarkBaselineWindow() {
  return _positiveIntEnv('SOCKET_TRANSPORT_BENCHMARK_BASELINE_WINDOW', 5);
}

bool _transportBenchmarkRequireBaseline() {
  return _envFlag('SOCKET_TRANSPORT_BENCHMARK_REQUIRE_BASELINE');
}

int _transportCompressionThresholdBytes() {
  return _positiveIntEnv(
    'SOCKET_TRANSPORT_BENCHMARK_COMPRESSION_THRESHOLD_BYTES',
    1024,
  );
}

int _transportLargePayloadRows() {
  return _positiveIntEnv('SOCKET_TRANSPORT_BENCHMARK_LARGE_ROWS', 256);
}

int _transportStreamChunkCount() {
  return _positiveIntEnv('SOCKET_TRANSPORT_BENCHMARK_STREAM_CHUNK_COUNT', 32);
}

int _transportRowsPerChunk() {
  return _positiveIntEnv(
    'SOCKET_TRANSPORT_BENCHMARK_STREAM_ROWS_PER_CHUNK',
    32,
  );
}

Map<String, int> _transportBenchmarkMaxMsByCase() {
  final thresholds = <String, int>{};

  void add(String suffix, String caseKey) {
    final raw = E2EEnv.get('SOCKET_TRANSPORT_BENCHMARK_MAX_MS_$suffix')?.trim();
    final parsed = int.tryParse(raw ?? '');
    if (parsed != null && parsed > 0) {
      thresholds[caseKey] = parsed;
    }
  }

  add('SMALL_ROUNDTRIP', _caseSmallRoundTrip);
  add('LARGE_GZIP', _caseLargeGzipRoundTrip);
  add('LARGE_AUTO', _caseLargeAutoRoundTrip);
  add('STREAM_CHUNKS_GZIP', _caseStreamChunksGzip);
  add('JUMBO_GZIP_ASYNC', _caseJumboGzipAsync);
  return thresholds;
}

String _buildMode() {
  if (kReleaseMode) {
    return 'release';
  }
  if (kProfileMode) {
    return 'profile';
  }
  return 'debug';
}

bool _transportIncludeJumbo() {
  return _envFlag('SOCKET_TRANSPORT_BENCHMARK_INCLUDE_JUMBO');
}

int _transportJumboBlobBytes() {
  return _positiveIntEnv(
    'SOCKET_TRANSPORT_BENCHMARK_JUMBO_BLOB_BYTES',
    280 * 1024,
  );
}

Map<String, dynamic> _benchmarkProfile() {
  return <String, dynamic>{
    'compression_threshold_bytes': _transportCompressionThresholdBytes(),
    'large_rows': _transportLargePayloadRows(),
    'stream_chunk_count': _transportStreamChunkCount(),
    'stream_rows_per_chunk': _transportRowsPerChunk(),
    'include_jumbo_isolate_path': _transportIncludeJumbo(),
    if (_transportIncludeJumbo()) 'jumbo_blob_bytes': _transportJumboBlobBytes(),
  };
}

Map<String, dynamic> _smallPayload() {
  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'req-small',
    'result': <String, dynamic>{'ok': true, 'value': 1},
  };
}

Map<String, dynamic> _largePayload(int rows) {
  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'req-large',
    'result': <String, dynamic>{
      'rows': List<Map<String, dynamic>>.generate(rows, (int index) {
        return <String, dynamic>{
          'id': index + 1,
          'code': 'code_${index + 1}',
          'amt': 10 + (index / 10),
          'description': 'payload row ${index + 1} ' * 3,
        };
      }),
    },
  };
}

Map<String, dynamic> _jumboRpcPayload(int blobBytes) {
  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 'req-jumbo',
    'result': <String, dynamic>{
      'blob': String.fromCharCodes(List<int>.filled(blobBytes, 0x5A)),
    },
  };
}

Map<String, dynamic> _streamChunkPayload(int chunkIndex, int rowsPerChunk) {
  return <String, dynamic>{
    'stream_id': 'stream-bench',
    'request_id': 'req-stream',
    'chunk_index': chunkIndex,
    'rows': List<Map<String, dynamic>>.generate(rowsPerChunk, (int rowIndex) {
      final id = (chunkIndex * rowsPerChunk) + rowIndex + 1;
      return <String, dynamic>{
        'id': id,
        'code': 'code_$id',
        'amt': 100 + (id / 100),
      };
    }),
    'column_metadata': const <Map<String, dynamic>>[
      <String, dynamic>{'name': 'id', 'type': 'int'},
      <String, dynamic>{'name': 'code', 'type': 'string'},
      <String, dynamic>{'name': 'amt', 'type': 'double'},
    ],
  };
}

Future<_TransportCaseMeasurement> _measureTransportCaseAsync(
  Future<_TransportIterationMeasurement> Function() body, {
  int warmup = 1,
  int iterations = 6,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }

  final elapsedSamples = <int>[];
  final originalBytesSamples = <int>[];
  final compressedBytesSamples = <int>[];
  final frameCountSamples = <int>[];
  final encodeLatencySamplesMs = <int>[];
  final decodeLatencySamplesMs = <int>[];
  final sendLatencySamplesMs = <int>[];

  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    final measurement = await body();
    stopwatch.stop();
    elapsedSamples.add(stopwatch.elapsedMilliseconds);
    originalBytesSamples.add(measurement.originalBytes);
    compressedBytesSamples.add(measurement.compressedBytes);
    frameCountSamples.add(measurement.frameCount);
    encodeLatencySamplesMs.add(measurement.encodeLatencyMs);
    decodeLatencySamplesMs.add(measurement.decodeLatencyMs);
    sendLatencySamplesMs.add(measurement.sendLatencyMs);
  }

  return _TransportCaseMeasurement(
    stats: E2eBenchmarkStats(
      warmup: warmup,
      iterations: iterations,
      samplesMs: elapsedSamples,
    ),
    originalBytesSamples: originalBytesSamples,
    compressedBytesSamples: compressedBytesSamples,
    frameCountSamples: frameCountSamples,
    encodeLatencySamplesMs: encodeLatencySamplesMs,
    decodeLatencySamplesMs: decodeLatencySamplesMs,
    sendLatencySamplesMs: sendLatencySamplesMs,
  );
}

Future<_TransportIterationMeasurement> _measureSingleRoundTrip({
  required TransportPipeline pipeline,
  required Map<String, dynamic> payload,
  required bool asyncReceive,
}) async {
  final encodeWatch = Stopwatch()..start();
  final prepareResult = await pipeline.prepareSendAsync(
    payload,
    traceId: 'trace-bench',
    requestId: payload['id']?.toString(),
  );
  encodeWatch.stop();
  expect(prepareResult.isSuccess(), isTrue);
  final frame = prepareResult.getOrThrow();
  final sendWatch = Stopwatch()..start();
  final wireFrame = PayloadFrame.fromJson(frame.toJson());
  sendWatch.stop();
  final decodeWatch = Stopwatch()..start();
  final receiveResult = asyncReceive
      ? await pipeline.receiveProcessAsync(wireFrame)
      : pipeline.receiveProcess(wireFrame);
  decodeWatch.stop();
  expect(receiveResult.isSuccess(), isTrue);
  expect(receiveResult.getOrThrow(), equals(payload));
  return _TransportIterationMeasurement(
    originalBytes: wireFrame.originalSize,
    compressedBytes: wireFrame.compressedSize,
    frameCount: 1,
    encodeLatencyMs: encodeWatch.elapsedMilliseconds,
    decodeLatencyMs: decodeWatch.elapsedMilliseconds,
    sendLatencyMs: sendWatch.elapsedMilliseconds,
  );
}

Future<_TransportIterationMeasurement> _measureChunkedStreamRoundTrip({
  required TransportPipeline pipeline,
  required int chunkCount,
  required int rowsPerChunk,
}) async {
  var totalOriginalBytes = 0;
  var totalCompressedBytes = 0;
  var totalEncodeLatencyMs = 0;
  var totalDecodeLatencyMs = 0;
  var totalSendLatencyMs = 0;

  for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
    final payload = _streamChunkPayload(chunkIndex, rowsPerChunk);
    final encodeWatch = Stopwatch()..start();
    final prepareResult = await pipeline.prepareSendAsync(
      payload,
      traceId: 'trace-stream-$chunkIndex',
      requestId: 'req-stream',
    );
    encodeWatch.stop();
    expect(prepareResult.isSuccess(), isTrue);
    final frame = prepareResult.getOrThrow();
    totalOriginalBytes += frame.originalSize;
    totalCompressedBytes += frame.compressedSize;
    totalEncodeLatencyMs += encodeWatch.elapsedMilliseconds;

    final sendWatch = Stopwatch()..start();
    final wireFrame = PayloadFrame.fromJson(frame.toJson());
    sendWatch.stop();
    totalSendLatencyMs += sendWatch.elapsedMilliseconds;
    final decodeWatch = Stopwatch()..start();
    final receiveResult = await pipeline.receiveProcessAsync(wireFrame);
    decodeWatch.stop();
    totalDecodeLatencyMs += decodeWatch.elapsedMilliseconds;
    expect(receiveResult.isSuccess(), isTrue);
    expect(receiveResult.getOrThrow(), equals(payload));
  }

  return _TransportIterationMeasurement(
    originalBytes: totalOriginalBytes,
    compressedBytes: totalCompressedBytes,
    frameCount: chunkCount,
    encodeLatencyMs: totalEncodeLatencyMs,
    decodeLatencyMs: totalDecodeLatencyMs,
    sendLatencyMs: totalSendLatencyMs,
  );
}

List<Map<String, dynamic>> _loadBaselineRecords(String configuredPath) {
  final file = resolveE2eBenchmarkOutputFile(configuredPath);
  if (!file.existsSync()) {
    return const <Map<String, dynamic>>[];
  }
  final lines = file.readAsLinesSync().where((String line) {
    return line.trim().isNotEmpty;
  });
  return parseE2eBenchmarkJsonlLines(lines);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadLiveTestEnv();

  if (!_envFlag('SOCKET_TRANSPORT_BENCHMARK')) {
    group('Socket transport benchmark', () {
      test(
        'skipped — enable SOCKET_TRANSPORT_BENCHMARK=true to run',
        () {},
        skip:
            'Defina SOCKET_TRANSPORT_BENCHMARK=true no .env para rodar o '
            'benchmark de transporte.',
      );
    });
    return;
  }

  final runId = const Uuid().v4();
  final largeRows = _transportLargePayloadRows();
  final streamChunkCount = _transportStreamChunkCount();
  final streamRowsPerChunk = _transportRowsPerChunk();
  final compressionThreshold = _transportCompressionThresholdBytes();
  final benchmarkProfile = _benchmarkProfile();
  final thresholds = _transportBenchmarkMaxMsByCase();

  group('Socket transport benchmark', () {
    test(
      'should measure transport pipeline round-trips and chunk overhead',
      () async {
        final smallPayload = _smallPayload();
        final largePayload = _largePayload(largeRows);
        final smallPipeline = TransportPipeline(
          encoding: 'json',
          compression: 'none',
          compressionThreshold: compressionThreshold,
        );
        final largeGzipPipeline = TransportPipeline(
          encoding: 'json',
          compression: 'gzip',
          compressionThreshold: compressionThreshold,
        );
        final largeAutoPipeline = TransportPipeline(
          encoding: 'json',
          compression: 'auto',
          compressionThreshold: compressionThreshold,
        );

        final smallRoundTrip = await _measureTransportCaseAsync(
          () => _measureSingleRoundTrip(
            pipeline: smallPipeline,
            payload: smallPayload,
            asyncReceive: false,
          ),
          iterations: 8,
        );
        final largeGzipRoundTrip = await _measureTransportCaseAsync(
          () => _measureSingleRoundTrip(
            pipeline: largeGzipPipeline,
            payload: largePayload,
            asyncReceive: true,
          ),
        );
        final largeAutoRoundTrip = await _measureTransportCaseAsync(
          () => _measureSingleRoundTrip(
            pipeline: largeAutoPipeline,
            payload: largePayload,
            asyncReceive: true,
          ),
        );
        final streamChunks = await _measureTransportCaseAsync(
          () => _measureChunkedStreamRoundTrip(
            pipeline: largeGzipPipeline,
            chunkCount: streamChunkCount,
            rowsPerChunk: streamRowsPerChunk,
          ),
          iterations: 4,
        );

        _TransportCaseMeasurement? jumboGzip;
        if (_transportIncludeJumbo()) {
          final jumboPayload = _jumboRpcPayload(_transportJumboBlobBytes());
          jumboGzip = await _measureTransportCaseAsync(
            () => _measureSingleRoundTrip(
              pipeline: largeGzipPipeline,
              payload: jumboPayload,
              asyncReceive: true,
            ),
            iterations: 3,
          );
        }

        final cases = <String, dynamic>{
          _caseSmallRoundTrip: smallRoundTrip.toJson(),
          _caseLargeGzipRoundTrip: largeGzipRoundTrip.toJson(),
          _caseLargeAutoRoundTrip: largeAutoRoundTrip.toJson(),
          _caseStreamChunksGzip: streamChunks.toJson(),
          if (jumboGzip != null) _caseJumboGzipAsync: jumboGzip.toJson(),
        };

        if (thresholds.isNotEmpty) {
          assertE2eBenchmarkWithinThresholds(
            cases: cases,
            thresholds: thresholds,
          );
        }

        final baselineFile = _transportBenchmarkBaselineFile();
        final maxRegressionPercent = _nonNegativeDoubleEnv(
          'SOCKET_TRANSPORT_BENCHMARK_MAX_REGRESSION_PERCENT',
        );
        if (baselineFile != null && maxRegressionPercent != null) {
          final comparableBaseline = selectComparableE2eBenchmarkRecords(
            records: _loadBaselineRecords(baselineFile),
            targetLabel: 'transport_local',
            buildMode: _buildMode(),
            benchmarkProfile: benchmarkProfile,
          );
          if (_transportBenchmarkRequireBaseline()) {
            expect(
              comparableBaseline,
              isNotEmpty,
              reason:
                  'No comparable transport benchmark baseline records found. '
                  'Record at least one run for the active benchmark profile.',
            );
          }
          if (comparableBaseline.isNotEmpty) {
            assertE2eBenchmarkWithinRegressionBudget(
              cases: cases,
              baselineRecords: comparableBaseline,
              maxRegressionPercent: maxRegressionPercent,
              maxRegressionMs: _positiveIntEnv(
                'SOCKET_TRANSPORT_BENCHMARK_MAX_REGRESSION_MS',
                8,
              ),
              window: _transportBenchmarkBaselineWindow(),
            );
          }
        }

        if (_envFlag('SOCKET_TRANSPORT_BENCHMARK_RECORD')) {
          final out = resolveE2eBenchmarkOutputFile(_transportBenchmarkFile());
          appendE2eBenchmarkRecord(
            file: out,
            record: <String, dynamic>{
              'schema_version': 2,
              'suite': 'socket_transport_benchmark',
              'run_id': runId,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
              'target_label': 'transport_local',
              'build_mode': _buildMode(),
              'git_revision': resolveE2eGitRevision(),
              'dart_platform': Platform.operatingSystem,
              'dart_version': Platform.version.split('\n').first,
              'benchmark_profile': benchmarkProfile,
              'cases': cases,
            },
          );
        }
      },
    );
  });
}
