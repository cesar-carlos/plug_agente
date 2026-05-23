/// Summary of protocol metrics.
class ProtocolMetricsSummary {
  const ProtocolMetricsSummary({
    required this.totalMessages,
    required this.protocolUsage,
    required this.compressionUsage,
    required this.requestedCompressionUsage,
    required this.eventUsage,
    required this.totalOriginalBytes,
    required this.totalCompressedBytes,
    required this.totalBytesSaved,
    required this.averageCompressionRatio,
    required this.successCount,
    required this.errorCount,
    required this.errorsByCode,
    required this.averageTotalDurationUs,
    required this.averageEncodeDurationUs,
    required this.averageCompressDurationUs,
    required this.averageDecodeDurationUs,
    required this.averageDecompressDurationUs,
    required this.averageSignDurationUs,
    required this.averageVerifyDurationUs,
    required this.averageCanonicalizeDurationUs,
    required this.averageSchemaValidateDurationUs,
    required this.totalDurationPercentiles,
    required this.encodeDurationPercentiles,
    required this.compressDurationPercentiles,
    required this.decodeDurationPercentiles,
    required this.decompressDurationPercentiles,
    required this.signDurationPercentiles,
    required this.verifyDurationPercentiles,
    required this.canonicalizeDurationPercentiles,
    required this.schemaValidateDurationPercentiles,
    required this.totalIsolateOperations,
    required this.jsonEncodeIsolateOperations,
    required this.gzipCompressIsolateOperations,
    required this.jsonDecodeIsolateOperations,
    required this.gzipDecompressIsolateOperations,
  });
  final int totalMessages;
  final Map<String, int> protocolUsage;
  final Map<String, int> compressionUsage;
  final Map<String, int> requestedCompressionUsage;
  final Map<String, int> eventUsage;
  final int totalOriginalBytes;
  final int totalCompressedBytes;
  final int totalBytesSaved;
  final double averageCompressionRatio;
  final int successCount;
  final int errorCount;
  final Map<int, int> errorsByCode;
  final double averageTotalDurationUs;
  final double averageEncodeDurationUs;
  final double averageCompressDurationUs;
  final double averageDecodeDurationUs;
  final double averageDecompressDurationUs;
  final double averageSignDurationUs;
  final double averageVerifyDurationUs;
  final double averageCanonicalizeDurationUs;
  final double averageSchemaValidateDurationUs;
  final ProtocolMetricDurationPercentiles totalDurationPercentiles;
  final ProtocolMetricDurationPercentiles encodeDurationPercentiles;
  final ProtocolMetricDurationPercentiles compressDurationPercentiles;
  final ProtocolMetricDurationPercentiles decodeDurationPercentiles;
  final ProtocolMetricDurationPercentiles decompressDurationPercentiles;
  final ProtocolMetricDurationPercentiles signDurationPercentiles;
  final ProtocolMetricDurationPercentiles verifyDurationPercentiles;
  final ProtocolMetricDurationPercentiles canonicalizeDurationPercentiles;
  final ProtocolMetricDurationPercentiles schemaValidateDurationPercentiles;
  final int totalIsolateOperations;
  final int jsonEncodeIsolateOperations;
  final int gzipCompressIsolateOperations;
  final int jsonDecodeIsolateOperations;
  final int gzipDecompressIsolateOperations;

  double get errorRate => totalMessages > 0 ? errorCount / totalMessages : 0.0;

  double get compressionEfficiency => totalOriginalBytes > 0 ? totalBytesSaved / totalOriginalBytes : 0.0;

  double get successRate => totalMessages > 0 ? successCount / totalMessages : 0.0;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'total_messages': totalMessages,
      'protocol_usage': protocolUsage,
      'compression_usage': compressionUsage,
      'requested_compression_usage': requestedCompressionUsage,
      'event_usage': eventUsage,
      'total_original_bytes': totalOriginalBytes,
      'total_compressed_bytes': totalCompressedBytes,
      'total_bytes_saved': totalBytesSaved,
      'average_compression_ratio': averageCompressionRatio,
      'compression_efficiency': compressionEfficiency,
      'success_count': successCount,
      'error_count': errorCount,
      'success_rate': successRate,
      'error_rate': errorRate,
      'errors_by_code': errorsByCode.map((code, count) => MapEntry(code.toString(), count)),
      'average_total_duration_us': averageTotalDurationUs,
      'average_encode_duration_us': averageEncodeDurationUs,
      'average_compress_duration_us': averageCompressDurationUs,
      'average_decode_duration_us': averageDecodeDurationUs,
      'average_decompress_duration_us': averageDecompressDurationUs,
      'average_sign_duration_us': averageSignDurationUs,
      'average_verify_duration_us': averageVerifyDurationUs,
      'average_canonicalize_duration_us': averageCanonicalizeDurationUs,
      'average_schema_validate_duration_us': averageSchemaValidateDurationUs,
      'total_duration_percentiles': totalDurationPercentiles.toJson(),
      'encode_duration_percentiles': encodeDurationPercentiles.toJson(),
      'compress_duration_percentiles': compressDurationPercentiles.toJson(),
      'decode_duration_percentiles': decodeDurationPercentiles.toJson(),
      'decompress_duration_percentiles': decompressDurationPercentiles.toJson(),
      'sign_duration_percentiles': signDurationPercentiles.toJson(),
      'verify_duration_percentiles': verifyDurationPercentiles.toJson(),
      'canonicalize_duration_percentiles': canonicalizeDurationPercentiles.toJson(),
      'schema_validate_duration_percentiles': schemaValidateDurationPercentiles.toJson(),
      'total_isolate_operations': totalIsolateOperations,
      'json_encode_isolate_operations': jsonEncodeIsolateOperations,
      'gzip_compress_isolate_operations': gzipCompressIsolateOperations,
      'json_decode_isolate_operations': jsonDecodeIsolateOperations,
      'gzip_decompress_isolate_operations': gzipDecompressIsolateOperations,
    };
  }
}

class ProtocolMetricDurationPercentiles {
  const ProtocolMetricDurationPercentiles({
    required this.p50Us,
    required this.p95Us,
    required this.p99Us,
  });

  factory ProtocolMetricDurationPercentiles.fromSamples(List<int> samples) {
    if (samples.isEmpty) {
      return const ProtocolMetricDurationPercentiles(
        p50Us: 0,
        p95Us: 0,
        p99Us: 0,
      );
    }
    final sorted = List<int>.of(samples)..sort();
    return ProtocolMetricDurationPercentiles(
      p50Us: _percentile(sorted, 0.50),
      p95Us: _percentile(sorted, 0.95),
      p99Us: _percentile(sorted, 0.99),
    );
  }

  final int p50Us;
  final int p95Us;
  final int p99Us;

  Map<String, int> toJson() {
    return {
      'p50_us': p50Us,
      'p95_us': p95Us,
      'p99_us': p99Us,
    };
  }

  static int _percentile(List<int> sorted, double percentile) {
    final index = ((sorted.length - 1) * percentile).ceil();
    return sorted[index];
  }
}
