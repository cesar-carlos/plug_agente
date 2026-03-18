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
    this.errorCode,
  });

  final DateTime timestamp;
  final String protocol;
  final String encoding;
  final String compression;
  final int originalSize;
  final int compressedSize;
  final String direction;
  final int? errorCode;

  double get compressionRatio => originalSize > 0 ? compressedSize / originalSize : 1.0;

  int get bytesSaved => originalSize - compressedSize;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'protocol': protocol,
      'encoding': encoding,
      'compression': compression,
      'original_size': originalSize,
      'compressed_size': compressedSize,
      'compression_ratio': compressionRatio,
      'bytes_saved': bytesSaved,
      'direction': direction,
      if (errorCode != null) 'error_code': errorCode,
    };
  }
}

/// Collector for protocol metrics.
class ProtocolMetricsCollector {
  ProtocolMetricsCollector();

  final List<ProtocolMetrics> _metrics = [];
  final StreamController<ProtocolMetrics> _metricsController =
      StreamController<ProtocolMetrics>.broadcast();

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
}

/// Summary of protocol metrics.
class ProtocolMetricsSummary {
  const ProtocolMetricsSummary({
    required this.totalMessages,
    required this.protocolUsage,
    required this.compressionUsage,
    required this.totalOriginalBytes,
    required this.totalCompressedBytes,
    required this.totalBytesSaved,
    required this.averageCompressionRatio,
    required this.errorCount,
    required this.errorsByCode,
  });

  factory ProtocolMetricsSummary.fromList(List<ProtocolMetrics> metrics) {
    final protocolCounts = <String, int>{};
    final compressionCounts = <String, int>{};
    final errorCounts = <int, int>{};

    var totalOriginal = 0;
    var totalCompressed = 0;
    var errorCount = 0;

    for (final metric in metrics) {
      protocolCounts[metric.protocol] = (protocolCounts[metric.protocol] ?? 0) + 1;
      compressionCounts[metric.compression] = (compressionCounts[metric.compression] ?? 0) + 1;

      totalOriginal += metric.originalSize;
      totalCompressed += metric.compressedSize;

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
      totalOriginalBytes: totalOriginal,
      totalCompressedBytes: totalCompressed,
      totalBytesSaved: totalOriginal - totalCompressed,
      averageCompressionRatio: avgRatio,
      errorCount: errorCount,
      errorsByCode: errorCounts,
    );
  }

  final int totalMessages;
  final Map<String, int> protocolUsage;
  final Map<String, int> compressionUsage;
  final int totalOriginalBytes;
  final int totalCompressedBytes;
  final int totalBytesSaved;
  final double averageCompressionRatio;
  final int errorCount;
  final Map<int, int> errorsByCode;

  double get errorRate => totalMessages > 0 ? errorCount / totalMessages : 0.0;

  double get compressionEfficiency => totalOriginalBytes > 0 ? totalBytesSaved / totalOriginalBytes : 0.0;
}
