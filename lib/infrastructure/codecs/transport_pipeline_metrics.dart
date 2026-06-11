import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';

void recordTransportPipelineMetric({
  required ProtocolMetricsCollector? metricsCollector,
  required String protocol,
  required String encoding,
  required String compression,
  required String direction,
  required String effectiveCompression,
  required int originalSize,
  required int compressedSize,
  required int totalDurationUs,
  String? eventName,
  int? encodeDurationUs,
  int? compressDurationUs,
  int? decodeDurationUs,
  int? decompressDurationUs,
  bool usedJsonEncodeIsolate = false,
  bool usedGzipCompressIsolate = false,
  bool usedJsonDecodeIsolate = false,
  bool usedGzipDecompressIsolate = false,
}) {
  metricsCollector?.record(
    ProtocolMetrics(
      timestamp: DateTime.now().toUtc(),
      protocol: protocol,
      encoding: encoding,
      compression: effectiveCompression,
      requestedCompression: compression,
      originalSize: originalSize,
      compressedSize: compressedSize,
      direction: direction,
      eventName: eventName,
      totalDurationUs: totalDurationUs,
      encodeDurationUs: encodeDurationUs,
      compressDurationUs: compressDurationUs,
      decodeDurationUs: decodeDurationUs,
      decompressDurationUs: decompressDurationUs,
      usedIsolate:
          usedJsonEncodeIsolate || usedGzipCompressIsolate || usedJsonDecodeIsolate || usedGzipDecompressIsolate,
      usedJsonEncodeIsolate: usedJsonEncodeIsolate,
      usedGzipCompressIsolate: usedGzipCompressIsolate,
      usedJsonDecodeIsolate: usedJsonDecodeIsolate,
      usedGzipDecompressIsolate: usedGzipDecompressIsolate,
    ),
  );
}
