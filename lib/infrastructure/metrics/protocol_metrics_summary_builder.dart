import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';

class ProtocolMetricsSummaryBuilder {
  const ProtocolMetricsSummaryBuilder._();

  static ProtocolMetricsSummary fromList(List<ProtocolMetrics> metrics) {
    final protocolCounts = <String, int>{};
    final compressionCounts = <String, int>{};
    final requestedCompressionCounts = <String, int>{};
    final eventCounts = <String, int>{};
    final errorCounts = <int, int>{};

    var totalOriginal = 0;
    var totalCompressed = 0;
    var successCount = 0;
    var errorCount = 0;
    var totalDurationUs = 0;
    var totalDurationSamples = 0;
    var encodeDurationUs = 0;
    var encodeDurationSamples = 0;
    var compressDurationUs = 0;
    var compressDurationSamples = 0;
    var decodeDurationUs = 0;
    var decodeDurationSamples = 0;
    var decompressDurationUs = 0;
    var decompressDurationSamples = 0;
    var signDurationUs = 0;
    var signDurationSamples = 0;
    var verifyDurationUs = 0;
    var verifyDurationSamples = 0;
    var canonicalizeDurationUs = 0;
    var canonicalizeDurationSamples = 0;
    var schemaValidateDurationUs = 0;
    var schemaValidateDurationSamples = 0;
    var totalIsolateOperations = 0;
    var jsonEncodeIsolateOperations = 0;
    var gzipCompressIsolateOperations = 0;
    var jsonDecodeIsolateOperations = 0;
    var gzipDecompressIsolateOperations = 0;

    final totalDurationValues = <int>[];
    final encodeDurationValues = <int>[];
    final compressDurationValues = <int>[];
    final decodeDurationValues = <int>[];
    final decompressDurationValues = <int>[];
    final signDurationValues = <int>[];
    final verifyDurationValues = <int>[];
    final canonicalizeDurationValues = <int>[];
    final schemaValidateDurationValues = <int>[];

    var transportMessageCount = 0;

    for (final metric in metrics) {
      if (metric.isTransportMessage) {
        transportMessageCount++;
        protocolCounts[metric.protocol] = (protocolCounts[metric.protocol] ?? 0) + 1;
        compressionCounts[metric.compression] = (compressionCounts[metric.compression] ?? 0) + 1;
        final requestedCompression = metric.requestedCompression;
        if (requestedCompression != null) {
          requestedCompressionCounts[requestedCompression] =
              (requestedCompressionCounts[requestedCompression] ?? 0) + 1;
        }
        final eventName = metric.eventName ?? 'unknown';
        eventCounts[eventName] = (eventCounts[eventName] ?? 0) + 1;

        totalOriginal += metric.originalSize;
        totalCompressed += metric.compressedSize;
        if (metric.success) {
          successCount++;
        }
        if (metric.totalDurationUs != null) {
          final value = metric.totalDurationUs!;
          totalDurationUs += value;
          totalDurationSamples++;
          totalDurationValues.add(value);
        }
        if (metric.encodeDurationUs != null) {
          final value = metric.encodeDurationUs!;
          encodeDurationUs += value;
          encodeDurationSamples++;
          encodeDurationValues.add(value);
        }
        if (metric.compressDurationUs != null) {
          final value = metric.compressDurationUs!;
          compressDurationUs += value;
          compressDurationSamples++;
          compressDurationValues.add(value);
        }
        if (metric.decodeDurationUs != null) {
          final value = metric.decodeDurationUs!;
          decodeDurationUs += value;
          decodeDurationSamples++;
          decodeDurationValues.add(value);
        }
        if (metric.decompressDurationUs != null) {
          final value = metric.decompressDurationUs!;
          decompressDurationUs += value;
          decompressDurationSamples++;
          decompressDurationValues.add(value);
        }
        if (metric.usedIsolate) {
          totalIsolateOperations++;
        }
        if (metric.usedJsonEncodeIsolate) {
          jsonEncodeIsolateOperations++;
        }
        if (metric.usedGzipCompressIsolate) {
          gzipCompressIsolateOperations++;
        }
        if (metric.usedJsonDecodeIsolate) {
          jsonDecodeIsolateOperations++;
        }
        if (metric.usedGzipDecompressIsolate) {
          gzipDecompressIsolateOperations++;
        }

        if (metric.errorCode != null) {
          errorCount++;
          errorCounts[metric.errorCode!] = (errorCounts[metric.errorCode!] ?? 0) + 1;
        }
      }
      if (metric.signDurationUs != null) {
        final value = metric.signDurationUs!;
        signDurationUs += value;
        signDurationSamples++;
        signDurationValues.add(value);
      }
      if (metric.verifyDurationUs != null) {
        final value = metric.verifyDurationUs!;
        verifyDurationUs += value;
        verifyDurationSamples++;
        verifyDurationValues.add(value);
      }
      if (metric.canonicalizeDurationUs != null) {
        final value = metric.canonicalizeDurationUs!;
        canonicalizeDurationUs += value;
        canonicalizeDurationSamples++;
        canonicalizeDurationValues.add(value);
      }
      if (metric.schemaValidateDurationUs != null) {
        final value = metric.schemaValidateDurationUs!;
        schemaValidateDurationUs += value;
        schemaValidateDurationSamples++;
        schemaValidateDurationValues.add(value);
      }
    }

    final avgRatio = totalOriginal > 0 ? totalCompressed / totalOriginal : 1.0;

    return ProtocolMetricsSummary(
      totalMessages: transportMessageCount,
      protocolUsage: protocolCounts,
      compressionUsage: compressionCounts,
      requestedCompressionUsage: requestedCompressionCounts,
      eventUsage: eventCounts,
      totalOriginalBytes: totalOriginal,
      totalCompressedBytes: totalCompressed,
      totalBytesSaved: totalOriginal - totalCompressed,
      averageCompressionRatio: avgRatio,
      successCount: successCount,
      errorCount: errorCount,
      errorsByCode: errorCounts,
      averageTotalDurationUs: totalDurationSamples > 0 ? totalDurationUs / totalDurationSamples : 0,
      averageEncodeDurationUs: encodeDurationSamples > 0 ? encodeDurationUs / encodeDurationSamples : 0,
      averageCompressDurationUs: compressDurationSamples > 0 ? compressDurationUs / compressDurationSamples : 0,
      averageDecodeDurationUs: decodeDurationSamples > 0 ? decodeDurationUs / decodeDurationSamples : 0,
      averageDecompressDurationUs: decompressDurationSamples > 0 ? decompressDurationUs / decompressDurationSamples : 0,
      averageSignDurationUs: signDurationSamples > 0 ? signDurationUs / signDurationSamples : 0,
      averageVerifyDurationUs: verifyDurationSamples > 0 ? verifyDurationUs / verifyDurationSamples : 0,
      averageCanonicalizeDurationUs: canonicalizeDurationSamples > 0
          ? canonicalizeDurationUs / canonicalizeDurationSamples
          : 0,
      averageSchemaValidateDurationUs: schemaValidateDurationSamples > 0
          ? schemaValidateDurationUs / schemaValidateDurationSamples
          : 0,
      totalDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(totalDurationValues),
      encodeDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(encodeDurationValues),
      compressDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(compressDurationValues),
      decodeDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(decodeDurationValues),
      decompressDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(decompressDurationValues),
      signDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(signDurationValues),
      verifyDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(verifyDurationValues),
      canonicalizeDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(canonicalizeDurationValues),
      schemaValidateDurationPercentiles: ProtocolMetricDurationPercentiles.fromSamples(schemaValidateDurationValues),
      totalIsolateOperations: totalIsolateOperations,
      jsonEncodeIsolateOperations: jsonEncodeIsolateOperations,
      gzipCompressIsolateOperations: gzipCompressIsolateOperations,
      jsonDecodeIsolateOperations: jsonDecodeIsolateOperations,
      gzipDecompressIsolateOperations: gzipDecompressIsolateOperations,
    );
  }
}
