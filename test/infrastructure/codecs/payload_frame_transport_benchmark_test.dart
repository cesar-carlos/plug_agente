@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

import '../../../tool/e2e_benchmark_summary.dart';
import '../../helpers/e2e_benchmark_assertions.dart';
import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

const String _caseOutboundSmallNone = 'payloadframe_outbound_small_none';
const String _caseOutboundSmallAuto = 'payloadframe_outbound_small_auto';
const String _caseOutboundMediumGzip = 'payloadframe_outbound_medium_gzip';
const String _caseOutboundMediumAuto = 'payloadframe_outbound_medium_auto';
const String _caseOutboundLargeGzipAsync = 'payloadframe_outbound_large_gzip_async';
const String _caseOutboundLargeAutoNotWorthIt = 'payloadframe_outbound_large_auto_not_worth_it';
const String _caseOutboundSignedGzip = 'payloadframe_outbound_signed_gzip';
const String _caseInboundSmallNone = 'payloadframe_inbound_small_none';
const String _caseInboundLargeGzipSync = 'payloadframe_inbound_large_gzip_sync';
const String _caseInboundLargeGzipAsync = 'payloadframe_inbound_large_gzip_async';
const String _caseRoundtripFrameGzip = 'payloadframe_roundtrip_frame_gzip';

class _FrameCaseMeasurement {
  const _FrameCaseMeasurement({
    required this.stats,
    required this.originalBytesSamples,
    required this.finalBytesSamples,
    required this.wireCompressionCounts,
    required this.compressionAttemptedCount,
    required this.usedAsyncEncodeCount,
    required this.usedAsyncDecodeCount,
    required this.usedSignatureCount,
    required this.autoFellBackToNoneCount,
  });

  final E2eBenchmarkStats stats;
  final List<int> originalBytesSamples;
  final List<int> finalBytesSamples;
  final Map<String, int> wireCompressionCounts;
  final int compressionAttemptedCount;
  final int usedAsyncEncodeCount;
  final int usedAsyncDecodeCount;
  final int usedSignatureCount;
  final int autoFellBackToNoneCount;

  Map<String, dynamic> toJson() {
    final originalMedian = _medianInt(originalBytesSamples);
    final finalMedian = _medianInt(finalBytesSamples);
    final bytesSaved = originalMedian > finalMedian ? originalMedian - finalMedian : 0;
    final compressionRatio = originalMedian > 0 ? finalMedian / originalMedian : 1.0;
    final dominantWireCompression = wireCompressionCounts.length == 1 ? wireCompressionCounts.keys.single : 'mixed';

    return <String, dynamic>{
      ...stats.toJson(),
      'original_bytes': originalMedian,
      'final_bytes': finalMedian,
      'wire_compression': dominantWireCompression,
      'wire_compression_counts': Map<String, int>.from(wireCompressionCounts),
      'bytes_saved': bytesSaved,
      'compression_ratio': compressionRatio,
      'compression_efficiency': originalMedian > 0 ? bytesSaved / originalMedian : 0.0,
      'compression_attempted': compressionAttemptedCount,
      'used_async_encode': usedAsyncEncodeCount,
      'used_async_decode': usedAsyncDecodeCount,
      'used_signature': usedSignatureCount,
      'auto_fell_back_to_none': autoFellBackToNoneCount,
      'original_bytes_samples': List<int>.from(originalBytesSamples),
      'final_bytes_samples': List<int>.from(finalBytesSamples),
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

String _payloadFrameBenchmarkFile() {
  final raw = E2EEnv.get('PAYLOAD_FRAME_BENCHMARK_FILE')?.trim();
  if (raw != null && raw.isNotEmpty) {
    return raw;
  }
  return 'benchmark${Platform.pathSeparator}payload_frame_transport.jsonl';
}

String? _payloadFrameBenchmarkBaselineFile() {
  final raw = E2EEnv.get('PAYLOAD_FRAME_BENCHMARK_BASELINE_FILE')?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
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

List<Map<String, dynamic>> _loadBaselineRecords(String configuredPath) {
  final file = resolveE2eBenchmarkOutputFile(configuredPath);
  if (!file.existsSync()) {
    return const <Map<String, dynamic>>[];
  }
  final lines = file.readAsLinesSync().where((line) => line.trim().isNotEmpty);
  return parseE2eBenchmarkJsonlLines(lines);
}

int _payloadFrameBenchmarkBaselineWindow() {
  return _positiveIntEnv('PAYLOAD_FRAME_BENCHMARK_BASELINE_WINDOW', 5);
}

bool _payloadFrameBenchmarkRequireBaseline() {
  return _envFlag('PAYLOAD_FRAME_BENCHMARK_REQUIRE_BASELINE');
}

bool _payloadFrameBenchmarkEnabled() {
  return _envFlag('PAYLOAD_FRAME_BENCHMARK');
}

bool _payloadFrameBenchmarkRecord() {
  return _envFlag('PAYLOAD_FRAME_BENCHMARK_RECORD');
}

int _frameBenchmarkIterations() {
  return _positiveIntEnv('PAYLOAD_FRAME_BENCHMARK_ITERATIONS', 15);
}

int _frameBenchmarkWarmup() {
  return _positiveIntEnv('PAYLOAD_FRAME_BENCHMARK_WARMUP', 3);
}

Map<String, dynamic> _generateSmallPayload() {
  return {
    'jsonrpc': '2.0',
    'result': {'rows': 5, 'elapsed_ms': 12},
    'id': 'req_small_001',
  };
}

Map<String, dynamic> _generateMediumPayload() {
  final rows = List<Map<String, dynamic>>.generate(
    100,
    (i) => {
      'id': i,
      'name': 'Row $i',
      'description': 'This is a compressible row with repeated text content.',
      'value': i * 1.5,
    },
  );
  return {
    'jsonrpc': '2.0',
    'result': {'rows': rows, 'elapsed_ms': 145},
    'id': 'req_medium_002',
  };
}

Map<String, dynamic> _generateLargeCompressiblePayload() {
  final rows = List<Map<String, dynamic>>.generate(
    5000,
    (i) => {
      'id': i,
      'name': 'Row $i',
      'description': 'This is a very long compressible row with a lot of repeated text content.',
      'value': i * 2.5,
      'extra': 'Some additional text to make this payload compressible.',
    },
  );
  return {
    'jsonrpc': '2.0',
    'result': {'rows': rows, 'elapsed_ms': 4500},
    'id': 'req_large_003',
  };
}

Map<String, dynamic> _generateLargeNonCompressiblePayload() {
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < 5000; i++) {
    rows.add({
      'id': i,
      'uuid': 'a1b2c3d4-e5f6-7890-abcd-${i.toString().padLeft(12, '0')}',
      'random': (i * 7919) % 10000,
    });
  }
  return {
    'jsonrpc': '2.0',
    'result': {'rows': rows, 'elapsed_ms': 3200},
    'id': 'req_non_compressible_004',
  };
}

_FrameCaseMeasurement _runFrameBenchmark({
  required String caseName,
  required String compression,
  required int compressionThreshold,
  required Map<String, dynamic> payload,
  required int warmup,
  required int iterations,
  bool useSignature = false,
  bool measureDecode = false,
}) {
  final samplesMs = <int>[];
  final originalBytesSamples = <int>[];
  final finalBytesSamples = <int>[];
  final wireCompressionCounts = <String, int>{};
  var compressionAttemptedCount = 0;
  const usedAsyncEncodeCount = 0;
  const usedAsyncDecodeCount = 0;
  var usedSignatureCount = 0;
  var autoFellBackToNoneCount = 0;

  final signer = useSignature ? PayloadSigner(keys: const {'dev': 'test_secret_key_for_benchmark'}) : null;

  for (var round = 0; round < warmup + iterations; round++) {
    final pipeline = TransportPipeline(
      encoding: 'json',
      compression: compression,
      compressionThreshold: compressionThreshold,
    );

    final sw = Stopwatch()..start();
    final prepareResult = pipeline.prepareSend(payload);
    sw.stop();

    if (prepareResult.isError()) {
      throw prepareResult.exceptionOrNull()!;
    }

    var frame = prepareResult.getOrThrow();
    final originalBytes = frame.originalSize;
    final finalBytes = frame.compressedSize;
    final wireCompression = frame.cmp;
    final compressionAttempted = compression != 'none' && originalBytes >= compressionThreshold;

    if (useSignature && signer != null) {
      frame = frame.copyWith(signature: signer.signFrame(frame).toJson());
      usedSignatureCount++;
    }

    final autoFellBack = compression == 'auto' && frame.cmp == 'none' && originalBytes >= compressionThreshold;
    if (autoFellBack) {
      autoFellBackToNoneCount++;
    }

    var decodeLatencyMs = 0;
    if (measureDecode) {
      final decodeSw = Stopwatch()..start();
      final decodeResult = pipeline.receiveProcess(frame);
      decodeSw.stop();
      decodeLatencyMs = decodeSw.elapsedMilliseconds;

      if (decodeResult.isError()) {
        throw decodeResult.exceptionOrNull()!;
      }
    }

    if (round >= warmup) {
      samplesMs.add(sw.elapsedMilliseconds + decodeLatencyMs);
      originalBytesSamples.add(originalBytes);
      finalBytesSamples.add(finalBytes);
      if (compressionAttempted) {
        compressionAttemptedCount++;
      }
      wireCompressionCounts[wireCompression] = (wireCompressionCounts[wireCompression] ?? 0) + 1;
    }
  }

  return _FrameCaseMeasurement(
    stats: E2eBenchmarkStats(
      warmup: warmup,
      iterations: iterations,
      samplesMs: samplesMs,
    ),
    originalBytesSamples: originalBytesSamples,
    finalBytesSamples: finalBytesSamples,
    wireCompressionCounts: wireCompressionCounts,
    compressionAttemptedCount: compressionAttemptedCount,
    usedAsyncEncodeCount: usedAsyncEncodeCount,
    usedAsyncDecodeCount: usedAsyncDecodeCount,
    usedSignatureCount: usedSignatureCount,
    autoFellBackToNoneCount: autoFellBackToNoneCount,
  );
}

Future<_FrameCaseMeasurement> _runFrameBenchmarkAsync({
  required String caseName,
  required String compression,
  required int compressionThreshold,
  required Map<String, dynamic> payload,
  required int warmup,
  required int iterations,
  bool useSignature = false,
  bool measureDecode = false,
}) async {
  final samplesMs = <int>[];
  final originalBytesSamples = <int>[];
  final finalBytesSamples = <int>[];
  final wireCompressionCounts = <String, int>{};
  var compressionAttemptedCount = 0;
  var usedAsyncEncodeCount = 0;
  var usedAsyncDecodeCount = 0;
  var usedSignatureCount = 0;
  var autoFellBackToNoneCount = 0;

  final signer = useSignature ? PayloadSigner(keys: const {'dev': 'test_secret_key_for_benchmark'}) : null;

  for (var round = 0; round < warmup + iterations; round++) {
    final pipeline = TransportPipeline(
      encoding: 'json',
      compression: compression,
      compressionThreshold: compressionThreshold,
    );

    final sw = Stopwatch()..start();
    final prepareResult = await pipeline.prepareSendAsync(payload);
    sw.stop();

    if (prepareResult.isError()) {
      throw prepareResult.exceptionOrNull()!;
    }

    var frame = prepareResult.getOrThrow();
    final originalBytes = frame.originalSize;
    final finalBytes = frame.compressedSize;
    final wireCompression = frame.cmp;
    final compressionAttempted = compression != 'none' && originalBytes >= compressionThreshold;

    usedAsyncEncodeCount++;

    if (useSignature && signer != null) {
      frame = frame.copyWith(signature: signer.signFrame(frame).toJson());
      usedSignatureCount++;
    }

    final autoFellBack = compression == 'auto' && frame.cmp == 'none' && originalBytes >= compressionThreshold;
    if (autoFellBack) {
      autoFellBackToNoneCount++;
    }

    var decodeLatencyMs = 0;
    if (measureDecode) {
      final decodeSw = Stopwatch()..start();
      final decodeResult = await pipeline.receiveProcessAsync(frame);
      decodeSw.stop();
      decodeLatencyMs = decodeSw.elapsedMilliseconds;
      usedAsyncDecodeCount++;

      if (decodeResult.isError()) {
        throw decodeResult.exceptionOrNull()!;
      }
    }

    if (round >= warmup) {
      samplesMs.add(sw.elapsedMilliseconds + decodeLatencyMs);
      originalBytesSamples.add(originalBytes);
      finalBytesSamples.add(finalBytes);
      if (compressionAttempted) {
        compressionAttemptedCount++;
      }
      wireCompressionCounts[wireCompression] = (wireCompressionCounts[wireCompression] ?? 0) + 1;
    }
  }

  return _FrameCaseMeasurement(
    stats: E2eBenchmarkStats(
      warmup: warmup,
      iterations: iterations,
      samplesMs: samplesMs,
    ),
    originalBytesSamples: originalBytesSamples,
    finalBytesSamples: finalBytesSamples,
    wireCompressionCounts: wireCompressionCounts,
    compressionAttemptedCount: compressionAttemptedCount,
    usedAsyncEncodeCount: usedAsyncEncodeCount,
    usedAsyncDecodeCount: usedAsyncDecodeCount,
    usedSignatureCount: usedSignatureCount,
    autoFellBackToNoneCount: autoFellBackToNoneCount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  loadLiveTestEnv();

  if (!_payloadFrameBenchmarkEnabled()) {
    group('PayloadFrame transport benchmark', () {
      test(
        'skipped — enable PAYLOAD_FRAME_BENCHMARK=true to run',
        () {},
        skip:
            'Defina PAYLOAD_FRAME_BENCHMARK=true no .env para rodar o benchmark '
            'de PayloadFrame.',
      );
    });
    return;
  }

  group('PayloadFrame transport benchmark', () {
    test(
      'outbound + inbound scenarios',
      () async {
        final warmup = _frameBenchmarkWarmup();
        final iterations = _frameBenchmarkIterations();
        final cases = <String, dynamic>{};

        final smallPayload = _generateSmallPayload();
        final mediumPayload = _generateMediumPayload();
        final largeCompressible = _generateLargeCompressiblePayload();
        final largeNonCompressible = _generateLargeNonCompressiblePayload();

        cases[_caseOutboundSmallNone] = _runFrameBenchmark(
          caseName: _caseOutboundSmallNone,
          compression: 'none',
          compressionThreshold: 1024,
          payload: smallPayload,
          warmup: warmup,
          iterations: iterations,
        ).toJson();

        cases[_caseOutboundSmallAuto] = _runFrameBenchmark(
          caseName: _caseOutboundSmallAuto,
          compression: 'auto',
          compressionThreshold: 1024,
          payload: smallPayload,
          warmup: warmup,
          iterations: iterations,
        ).toJson();

        cases[_caseOutboundMediumGzip] = _runFrameBenchmark(
          caseName: _caseOutboundMediumGzip,
          compression: 'gzip',
          compressionThreshold: 1024,
          payload: mediumPayload,
          warmup: warmup,
          iterations: iterations,
        ).toJson();

        cases[_caseOutboundMediumAuto] = _runFrameBenchmark(
          caseName: _caseOutboundMediumAuto,
          compression: 'auto',
          compressionThreshold: 1024,
          payload: mediumPayload,
          warmup: warmup,
          iterations: iterations,
        ).toJson();

        cases[_caseOutboundLargeGzipAsync] = (await _runFrameBenchmarkAsync(
          caseName: _caseOutboundLargeGzipAsync,
          compression: 'gzip',
          compressionThreshold: 1024,
          payload: largeCompressible,
          warmup: warmup,
          iterations: iterations,
        )).toJson();

        cases[_caseOutboundLargeAutoNotWorthIt] = (await _runFrameBenchmarkAsync(
          caseName: _caseOutboundLargeAutoNotWorthIt,
          compression: 'auto',
          compressionThreshold: 1024,
          payload: largeNonCompressible,
          warmup: warmup,
          iterations: iterations,
        )).toJson();

        cases[_caseOutboundSignedGzip] = _runFrameBenchmark(
          caseName: _caseOutboundSignedGzip,
          compression: 'gzip',
          compressionThreshold: 1024,
          payload: mediumPayload,
          warmup: warmup,
          iterations: iterations,
          useSignature: true,
        ).toJson();

        cases[_caseInboundSmallNone] = _runFrameBenchmark(
          caseName: _caseInboundSmallNone,
          compression: 'none',
          compressionThreshold: 1024,
          payload: smallPayload,
          warmup: warmup,
          iterations: iterations,
          measureDecode: true,
        ).toJson();

        cases[_caseInboundLargeGzipSync] = _runFrameBenchmark(
          caseName: _caseInboundLargeGzipSync,
          compression: 'gzip',
          compressionThreshold: 1024,
          payload: mediumPayload,
          warmup: warmup,
          iterations: iterations,
          measureDecode: true,
        ).toJson();

        cases[_caseInboundLargeGzipAsync] = (await _runFrameBenchmarkAsync(
          caseName: _caseInboundLargeGzipAsync,
          compression: 'gzip',
          compressionThreshold: 1024,
          payload: largeCompressible,
          warmup: warmup,
          iterations: iterations,
          measureDecode: true,
        )).toJson();

        cases[_caseRoundtripFrameGzip] = _runFrameBenchmark(
          caseName: _caseRoundtripFrameGzip,
          compression: 'gzip',
          compressionThreshold: 1024,
          payload: mediumPayload,
          warmup: warmup,
          iterations: iterations,
          measureDecode: true,
        ).toJson();

        final baselineFile = _payloadFrameBenchmarkBaselineFile();
        final baselineWindow = _payloadFrameBenchmarkBaselineWindow();
        final requireBaseline = _payloadFrameBenchmarkRequireBaseline();
        final maxRegressionPercent = _nonNegativeDoubleEnv('PAYLOAD_FRAME_BENCHMARK_MAX_REGRESSION_PERCENT') ?? 10.0;
        final maxRegressionMs = _positiveIntEnv('PAYLOAD_FRAME_BENCHMARK_MAX_REGRESSION_MS', 5);

        if (baselineFile != null && maxRegressionPercent > 0) {
          final benchmarkProfile = <String, dynamic>{
            'warmup': warmup,
            'iterations': iterations,
            'compression_threshold': 1024,
          };
          final comparableBaseline = selectComparableE2eBenchmarkRecords(
            records: _loadBaselineRecords(baselineFile),
            targetLabel: 'payload_frame_local',
            buildMode: _buildMode(),
            benchmarkProfile: benchmarkProfile,
          );
          if (requireBaseline) {
            expect(
              comparableBaseline,
              isNotEmpty,
              reason: 'No comparable payload frame benchmark baseline records found.',
            );
          }
          if (comparableBaseline.isNotEmpty) {
            assertE2eBenchmarkWithinRegressionBudget(
              cases: cases,
              baselineRecords: comparableBaseline,
              maxRegressionPercent: maxRegressionPercent,
              maxRegressionMs: maxRegressionMs,
              window: baselineWindow,
            );
          }
        }

        if (_payloadFrameBenchmarkRecord()) {
          final outputPath = _payloadFrameBenchmarkFile();
          final record = <String, dynamic>{
            'schema_version': 2,
            'suite': 'payload_frame_transport_benchmark',
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'target_label': 'payload_frame_local',
            'build_mode': _buildMode(),
            'git_revision': resolveE2eGitRevision(),
            'dart_platform': Platform.operatingSystem,
            'dart_version': Platform.version.split('\n').first,
            'benchmark_profile': {
              'warmup': warmup,
              'iterations': iterations,
              'compression_threshold': 1024,
            },
            'cases': cases,
          };
          final out = resolveE2eBenchmarkOutputFile(outputPath);
          appendE2eBenchmarkRecord(file: out, record: record);
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
