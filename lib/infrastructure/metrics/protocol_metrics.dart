import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';
import 'package:plug_agente/domain/repositories/i_protocol_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics_summary_builder.dart';

export 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';
export 'protocol_metrics_summary_builder.dart';

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

  bool get isTransportMessage => direction == 'send' || direction == 'receive';

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
class ProtocolMetricsCollector implements IProtocolMetricsCollector {
  ProtocolMetricsCollector({
    int maxEntries = 1000,
  }) : _maxEntries = maxEntries < 1 ? 1 : maxEntries;

  // ListQueue keeps `record` O(1) at the ring-buffer cap. Using a plain List
  // forced `removeRange(0, 1)` on every record at cap, an O(n) shift on the
  // transport hot path — every send/receive runs through this collector.
  final ListQueue<ProtocolMetrics> _metrics = ListQueue<ProtocolMetrics>();
  final StreamController<ProtocolMetrics> _metricsController = StreamController<ProtocolMetrics>.broadcast();
  final StreamController<void> _updates = StreamController<void>.broadcast(sync: true);
  final int _maxEntries;

  Stream<ProtocolMetrics> get metricsStream => _metricsController.stream;

  @override
  Stream<void> get updates => _updates.stream;

  List<ProtocolMetrics> get metrics => List.unmodifiable(_metrics);

  void record(ProtocolMetrics metrics) {
    _metrics.addLast(metrics);

    while (_metrics.length > _maxEntries) {
      _metrics.removeFirst();
    }

    if (!_metricsController.isClosed) {
      _metricsController.add(metrics);
    }
    if (!_updates.isClosed) {
      _updates.add(null);
    }
  }

  void clear() {
    _metrics.clear();
  }

  void dispose() {
    _metricsController.close();
    _updates.close();
  }

  @override
  ProtocolMetricsSummary getSummary({Duration? period}) {
    final now = DateTime.now();
    final cutoff = period != null ? now.subtract(period) : null;

    final filtered = cutoff != null
        ? _metrics.where((m) => m.timestamp.isAfter(cutoff)).toList(growable: false)
        : _metrics.toList(growable: false);

    return ProtocolMetricsSummaryBuilder.fromList(filtered);
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
      result[event] = ProtocolMetricsSummaryBuilder.fromList(values);
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
    final filtered = cutoff != null
        ? _metrics.where((m) => m.timestamp.isAfter(cutoff)).toList(growable: false)
        : _metrics.toList(growable: false);
    if (maxPoints <= 0 || filtered.isEmpty) {
      return const <ProtocolMetrics>[];
    }
    final start = filtered.length > maxPoints ? filtered.length - maxPoints : 0;
    return List<ProtocolMetrics>.unmodifiable(filtered.sublist(start));
  }
}
