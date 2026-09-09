import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

Future<Map<String, dynamic>> runTransportPipelineBenchmarkCaseAsync({
  required Map<String, dynamic> payload,
  required String benchmarkCaseName,
  required String compressionMode,
  required bool signed,
  required int iterations,
  required int threshold,
  required int gzipIsolateThresholdBytes,
}) async {
  final collector = ProtocolMetricsCollector(maxEntries: iterations * 2 + 4);
  final signer = signed
      ? PayloadSigner(
          keys: const <String, String>{'benchmark': 'benchmark-secret'},
          activeKeyId: 'benchmark',
        )
      : null;
  final pipeline = TransportPipeline(
    encoding: 'json',
    compression: compressionMode,
    compressionThreshold: threshold,
    gzipIsolateThresholdBytes: gzipIsolateThresholdBytes,
    metricsCollector: collector,
  );

  for (var i = 0; i < iterations; i++) {
    final prepareResult = await pipeline.prepareSendAsync(
      payload,
      metricEventName: benchmarkCaseName,
    );
    final frame = prepareResult.getOrThrow();
    final wireFrame = await _signAndVerifyFrame(
      frame: frame,
      signer: signer,
      collector: collector,
      eventName: benchmarkCaseName,
    );
    await pipeline.receiveProcessAsync(wireFrame, metricEventName: benchmarkCaseName);
  }

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
    'case': benchmarkCaseName,
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
    'compress_p50_us': summary.compressDurationPercentiles.p50Us,
    'compress_p95_us': summary.compressDurationPercentiles.p95Us,
    'compress_p99_us': summary.compressDurationPercentiles.p99Us,
    'decompress_p50_us': summary.decompressDurationPercentiles.p50Us,
    'decompress_p95_us': summary.decompressDurationPercentiles.p95Us,
    'decompress_p99_us': summary.decompressDurationPercentiles.p99Us,
    'sign_p50_us': summary.signDurationPercentiles.p50Us,
    'sign_p95_us': summary.signDurationPercentiles.p95Us,
    'sign_p99_us': summary.signDurationPercentiles.p99Us,
    'verify_p50_us': summary.verifyDurationPercentiles.p50Us,
    'verify_p95_us': summary.verifyDurationPercentiles.p95Us,
    'verify_p99_us': summary.verifyDurationPercentiles.p99Us,
    'isolate_operations': summary.totalIsolateOperations,
    'json_encode_isolate_operations': summary.jsonEncodeIsolateOperations,
    'gzip_compress_isolate_operations': summary.gzipCompressIsolateOperations,
    'json_decode_isolate_operations': summary.jsonDecodeIsolateOperations,
    'gzip_decompress_isolate_operations': summary.gzipDecompressIsolateOperations,
    'hmac_sign_isolate_operations': summary.hmacSignIsolateOperations,
    'hmac_verify_isolate_operations': summary.hmacVerifyIsolateOperations,
    'summary': summary.toJson(),
  };
}

Future<PayloadFrame> _signAndVerifyFrame({
  required PayloadFrame frame,
  required PayloadSigner? signer,
  required ProtocolMetricsCollector collector,
  required String eventName,
}) async {
  if (signer == null) {
    return frame;
  }
  final useIsolate = frame.originalSize > ConnectionConstants.signingIsolateThresholdBytes;
  final signing = useIsolate ? await signer.signFrameAsync(frame) : signer.signFrameWithMetrics(frame);
  final signedFrame = frame.copyWith(signature: signing.signature.toJson());
  collector.record(
    ProtocolMetrics(
      timestamp: DateTime.now().toUtc(),
      protocol: 'jsonrpc-v2',
      encoding: frame.enc,
      compression: frame.cmp,
      originalSize: frame.originalSize,
      compressedSize: frame.compressedSize,
      direction: 'sign',
      eventName: eventName,
      totalDurationUs: signing.metrics.canonicalizeDurationUs + (signing.metrics.signDurationUs ?? 0),
      signDurationUs: signing.metrics.signDurationUs,
      canonicalizeDurationUs: signing.metrics.canonicalizeDurationUs,
      usedIsolate: useIsolate,
      usedHmacSignIsolate: useIsolate,
    ),
  );
  final verification = useIsolate
      ? await signer.verifyFrameAsyncWithMetrics(signedFrame, signing.signature)
      : signer.verifyFrameWithMetrics(signedFrame, signing.signature);
  if (!verification.isValid) {
    throw StateError('Benchmark signature verification failed');
  }
  collector.record(
    ProtocolMetrics(
      timestamp: DateTime.now().toUtc(),
      protocol: 'jsonrpc-v2',
      encoding: frame.enc,
      compression: frame.cmp,
      originalSize: frame.originalSize,
      compressedSize: frame.compressedSize,
      direction: 'verify',
      eventName: eventName,
      totalDurationUs: verification.metrics.canonicalizeDurationUs + (verification.metrics.verifyDurationUs ?? 0),
      verifyDurationUs: verification.metrics.verifyDurationUs,
      canonicalizeDurationUs: verification.metrics.canonicalizeDurationUs,
      usedIsolate: useIsolate,
      usedHmacVerifyIsolate: useIsolate,
    ),
  );
  return signedFrame;
}
