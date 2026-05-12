import 'dart:async';

/// Metrics for protocol usage and performance.
class ProtocolMetrics {
  ProtocolMetrics({
    required this.timestamp,
    required this.protocol,
    required this.encoding,
    required this.compression,
    required this.originalSize,
    required this.compressedSize,
    required this.direction,
    this.eventName,
    this.requestedCompression,
    this.success = true,
    this.totalDurationUs,
    this.encodeDurationUs,
    this.compressDurationUs,
    this.decodeDurationUs,
    this.decompressDurationUs,
    this.signDurationUs,
    this.verifyDurationUs,
    this.canonicalizeDurationUs,
    this.schemaValidateDurationUs,
    this.usedIsolate = false,
    this.usedJsonEncodeIsolate = false,
    this.usedGzipCompressIsolate = false,
    this.usedJsonDecodeIsolate = false,
    this.usedGzipDecompressIsolate = false,
    this.errorCode,
  });

  final DateTime timestamp;
  final String protocol;
  final String encoding;
  final String compression;
  final int originalSize;
  final int compressedSize;
  final String direction;
  final String? eventName;
  final String? requestedCompression;
  final bool success;
  final int? totalDurationUs;
  final int? encodeDurationUs;
  final int? compressDurationUs;
  final int? decodeDurationUs;
  final int? decompressDurationUs;
  final int? signDurationUs;
  final int? verifyDurationUs;
  final int? canonicalizeDurationUs;
  final int? schemaValidateDurationUs;
  final bool usedIsolate;
  final bool usedJsonEncodeIsolate;
  final bool usedGzipCompressIsolate;
  final bool usedJsonDecodeIsolate;
  final bool usedGzipDecompressIsolate;
  final int? errorCode;

  double get compressionRatio => originalSize > 0 ? compressedSize / originalSize : 1.0;

  int get bytesSaved => originalSize - compressedSize;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'protocol': protocol,
      'encoding': encoding,
      'compression': compression,
      if (requestedCompression != null) 'requested_compression': requestedCompression,
      'original_size': originalSize,
      'compressed_size': compressedSize,
      'compression_ratio': compressionRatio,
      'bytes_saved': bytesSaved,
      'direction': direction,
      if (eventName != null) 'event_name': eventName,
      'success': success,
      if (totalDurationUs != null) 'total_duration_us': totalDurationUs,
      if (encodeDurationUs != null) 'encode_duration_us': encodeDurationUs,
      if (compressDurationUs != null) 'compress_duration_us': compressDurationUs,
      if (decodeDurationUs != null) 'decode_duration_us': decodeDurationUs,
      if (decompressDurationUs != null) 'decompress_duration_us': decompressDurationUs,
      if (signDurationUs != null) 'sign_duration_us': signDurationUs,
      if (verifyDurationUs != null) 'verify_duration_us': verifyDurationUs,
      if (canonicalizeDurationUs != null) 'canonicalize_duration_us': canonicalizeDurationUs,
      if (schemaValidateDurationUs != null) 'schema_validate_duration_us': schemaValidateDurationUs,
      'used_isolate': usedIsolate,
      'used_json_encode_isolate': usedJsonEncodeIsolate,
      'used_gzip_compress_isolate': usedGzipCompressIsolate,
      'used_json_decode_isolate': usedJsonDecodeIsolate,
      'used_gzip_decompress_isolate': usedGzipDecompressIsolate,
      if (errorCode != null) 'error_code': errorCode,
    };
  }
}

/// Collector for protocol metrics.
class ProtocolMetricsCollector {
  ProtocolMetricsCollector({
    int maxEntries = 1000,
  }) : _maxEntries = maxEntries < 1 ? 1 : maxEntries;

  final List<ProtocolMetrics> _metrics = [];
  final StreamController<ProtocolMetrics> _metricsController = StreamController<ProtocolMetrics>.broadcast();
  final int _maxEntries;

  Stream<ProtocolMetrics> get metricsStream => _metricsController.stream;

  List<ProtocolMetrics> get metrics => List.unmodifiable(_metrics);

  void record(ProtocolMetrics metrics) {
    _metrics.add(metrics);

    if (_metrics.length > _maxEntries) {
      _metrics.removeRange(0, _metrics.length - _maxEntries);
    }

    if (!_metricsController.isClosed) {
      _metricsController.add(metrics);
    }
  }

  void clear() {
    _metrics.clear();
  }

  void dispose() {
    _metricsController.close();
  }

  /// Gets metrics summary for a time period.
  ProtocolMetricsSummary getSummary({Duration? period}) {
    final now = DateTime.now();
    final cutoff = period != null ? now.subtract(period) : null;

    final filtered = cutoff != null ? _metrics.where((m) => m.timestamp.isAfter(cutoff)).toList() : _metrics;

    return ProtocolMetricsSummary.fromList(filtered);
  }

  /// Aggregated summary grouped by event name.
  ///
  /// Metrics without an explicit event are grouped as `unknown`.
  Map<String, ProtocolMetricsSummary> getSummaryByEvent({Duration? period}) {
    final now = DateTime.now();
    final cutoff = period != null ? now.subtract(period) : null;
    final filtered = cutoff != null ? _metrics.where((m) => m.timestamp.isAfter(cutoff)) : _metrics;

    final grouped = <String, List<ProtocolMetrics>>{};
    for (final metric in filtered) {
      final key = metric.eventName ?? 'unknown';
      grouped.putIfAbsent(key, () => <ProtocolMetrics>[]).add(metric);
    }

    final result = <String, ProtocolMetricsSummary>{};
    grouped.forEach((event, values) {
      result[event] = ProtocolMetricsSummary.fromList(values);
    });
    return result;
  }

  /// Most recent metrics time series (short rolling window for dashboards/logging).
  List<ProtocolMetrics> getRecentSeries({
    int maxPoints = 60,
    Duration? period,
  }) {
    final now = DateTime.now();
    final cutoff = period != null ? now.subtract(period) : null;
    final filtered = cutoff != null ? _metrics.where((m) => m.timestamp.isAfter(cutoff)).toList() : _metrics;
    if (maxPoints <= 0 || filtered.isEmpty) {
      return const <ProtocolMetrics>[];
    }
    final start = filtered.length > maxPoints ? filtered.length - maxPoints : 0;
    return List<ProtocolMetrics>.unmodifiable(filtered.sublist(start));
  }
}

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

  factory ProtocolMetricsSummary.fromList(List<ProtocolMetrics> metrics) {
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

    for (final metric in metrics) {
      protocolCounts[metric.protocol] = (protocolCounts[metric.protocol] ?? 0) + 1;
      compressionCounts[metric.compression] = (compressionCounts[metric.compression] ?? 0) + 1;
      final requestedCompression = metric.requestedCompression;
      if (requestedCompression != null) {
        requestedCompressionCounts[requestedCompression] = (requestedCompressionCounts[requestedCompression] ?? 0) + 1;
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

    final avgRatio = totalOriginal > 0 ? totalCompressed / totalOriginal : 1.0;

    return ProtocolMetricsSummary(
      totalMessages: metrics.length,
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
