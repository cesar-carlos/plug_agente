import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';

void main() {
  group('ProtocolMetrics', () {
    test('should calculate compression ratio correctly', () {
      final metrics = ProtocolMetrics(
        timestamp: DateTime.now(),
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
        originalSize: 1000,
        compressedSize: 500,
        direction: 'send',
      );

      expect(metrics.compressionRatio, equals(0.5));
      expect(metrics.bytesSaved, equals(500));
    });

    test('should handle no compression case', () {
      final metrics = ProtocolMetrics(
        timestamp: DateTime.now(),
        protocol: 'legacy-envelope-v1',
        encoding: 'json',
        compression: 'none',
        originalSize: 1000,
        compressedSize: 1000,
        direction: 'send',
      );

      expect(metrics.compressionRatio, equals(1.0));
      expect(metrics.bytesSaved, equals(0));
    });
  });

  group('ProtocolMetricsCollector', () {
    late ProtocolMetricsCollector collector;

    setUp(() {
      collector = ProtocolMetricsCollector();
      collector.clear();
    });

    test('should record metrics', () {
      final metrics = ProtocolMetrics(
        timestamp: DateTime.now(),
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
        originalSize: 1000,
        compressedSize: 500,
        direction: 'send',
      );

      collector.record(metrics);

      expect(collector.metrics, hasLength(1));
      expect(collector.metrics.first, equals(metrics));
    });

    test('should emit metrics to stream', () async {
      final metrics = ProtocolMetrics(
        timestamp: DateTime.now(),
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
        originalSize: 1000,
        compressedSize: 500,
        direction: 'send',
      );

      final streamFuture = collector.metricsStream.first;
      collector.record(metrics);

      final emitted = await streamFuture;
      expect(emitted, equals(metrics));
    });

    test('should limit metrics to 1000 entries', () {
      for (var i = 0; i < 1100; i++) {
        collector.record(
          ProtocolMetrics(
            timestamp: DateTime.now(),
            protocol: 'jsonrpc-v2',
            encoding: 'json',
            compression: 'none',
            originalSize: 100,
            compressedSize: 100,
            direction: 'send',
          ),
        );
      }

      expect(collector.metrics.length, equals(1000));
    });
  });

  group('ProtocolMetricsSummary', () {
    test('should calculate summary statistics', () {
      final metrics = [
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          originalSize: 1000,
          compressedSize: 500,
          direction: 'send',
        ),
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          originalSize: 2000,
          compressedSize: 1000,
          direction: 'receive',
        ),
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'legacy-envelope-v1',
          encoding: 'json',
          compression: 'none',
          originalSize: 500,
          compressedSize: 500,
          direction: 'send',
        ),
      ];

      final summary = ProtocolMetricsSummary.fromList(metrics);

      expect(summary.totalMessages, equals(3));
      expect(summary.totalOriginalBytes, equals(3500));
      expect(summary.totalCompressedBytes, equals(2000));
      expect(summary.totalBytesSaved, equals(1500));
      expect(summary.protocolUsage['jsonrpc-v2'], equals(2));
      expect(summary.protocolUsage['legacy-envelope-v1'], equals(1));
      expect(summary.compressionUsage['gzip'], equals(2));
      expect(summary.compressionUsage['none'], equals(1));
    });

    test('should calculate error rate', () {
      final metrics = [
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
          originalSize: 100,
          compressedSize: 100,
          direction: 'send',
        ),
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
          originalSize: 100,
          compressedSize: 100,
          direction: 'send',
          errorCode: -32102,
        ),
      ];

      final summary = ProtocolMetricsSummary.fromList(metrics);

      expect(summary.errorCount, equals(1));
      expect(summary.errorRate, equals(0.5));
      expect(summary.errorsByCode[-32102], equals(1));
    });

    test('should handle empty metrics list', () {
      final summary = ProtocolMetricsSummary.fromList([]);

      expect(summary.totalMessages, equals(0));
      expect(summary.totalOriginalBytes, equals(0));
      expect(summary.totalCompressedBytes, equals(0));
      expect(summary.errorRate, equals(0.0));
    });
  });
}
