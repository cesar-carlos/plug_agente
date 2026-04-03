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
  ProtocolMetricsCollector();

  final List<ProtocolMetrics> _metrics = [];
  final StreamController<ProtocolMetrics> _metricsController = StreamController<ProtocolMetrics>.broadcast();

  Stream<ProtocolMetrics> get metricsStream => _metricsController.stream;

  List<ProtocolMetrics> get metrics => List.unmodifiable(_metrics);

  void record(ProtocolMetrics metrics) {
    _metrics.add(metrics);

    if (_metrics.length > 1000) {
      _metrics.removeAt(0);
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
    var totalIsolateOperations = 0;
    var jsonEncodeIsolateOperations = 0;
    var gzipCompressIsolateOperations = 0;
    var jsonDecodeIsolateOperations = 0;
    var gzipDecompressIsolateOperations = 0;

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
        totalDurationUs += metric.totalDurationUs!;
        totalDurationSamples++;
      }
      if (metric.encodeDurationUs != null) {
        encodeDurationUs += metric.encodeDurationUs!;
        encodeDurationSamples++;
      }
      if (metric.compressDurationUs != null) {
        compressDurationUs += metric.compressDurationUs!;
        compressDurationSamples++;
      }
      if (metric.decodeDurationUs != null) {
        decodeDurationUs += metric.decodeDurationUs!;
        decodeDurationSamples++;
      }
      if (metric.decompressDurationUs != null) {
        decompressDurationUs += metric.decompressDurationUs!;
        decompressDurationSamples++;
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
  final int totalIsolateOperations;
  final int jsonEncodeIsolateOperations;
  final int gzipCompressIsolateOperations;
  final int jsonDecodeIsolateOperations;
  final int gzipDecompressIsolateOperations;

  double get errorRate => totalMessages > 0 ? errorCount / totalMessages : 0.0;

  double get compressionEfficiency => totalOriginalBytes > 0 ? totalBytesSaved / totalOriginalBytes : 0.0;

  double get successRate => totalMessages > 0 ? successCount / totalMessages : 0.0;
}
