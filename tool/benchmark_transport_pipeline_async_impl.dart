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
    final wireFrame = signer == null ? frame : frame.copyWith(signature: signer.signFrame(frame).toJson());
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
    'isolate_operations': summary.totalIsolateOperations,
    'json_encode_isolate_operations': summary.jsonEncodeIsolateOperations,
    'gzip_compress_isolate_operations': summary.gzipCompressIsolateOperations,
    'json_decode_isolate_operations': summary.jsonDecodeIsolateOperations,
    'gzip_decompress_isolate_operations': summary.gzipDecompressIsolateOperations,
    'summary': summary.toJson(),
  };
}
