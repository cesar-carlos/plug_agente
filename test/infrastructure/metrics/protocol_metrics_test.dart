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
        requestedCompression: 'auto',
        originalSize: 1000,
        compressedSize: 500,
        direction: 'send',
        eventName: 'rpc:response',
        totalDurationUs: 1200,
        encodeDurationUs: 400,
        compressDurationUs: 700,
        usedIsolate: true,
        usedGzipCompressIsolate: true,
      );

      expect(metrics.compressionRatio, equals(0.5));
      expect(metrics.bytesSaved, equals(500));
      expect(metrics.toJson()['requested_compression'], equals('auto'));
      expect(metrics.toJson()['used_gzip_compress_isolate'], isTrue);
      expect(metrics.toJson()['event_name'], equals('rpc:response'));
    });

    test('should handle no compression case', () {
      final metrics = ProtocolMetrics(
        timestamp: DateTime.now(),
        protocol: 'jsonrpc-v2',
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

    test('should return summary grouped by event', () {
      collector.record(
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
          originalSize: 100,
          compressedSize: 100,
          direction: 'send',
          eventName: 'rpc:response',
        ),
      );
      collector.record(
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          originalSize: 100,
          compressedSize: 50,
          direction: 'receive',
          eventName: 'rpc:request',
        ),
      );

      final byEvent = collector.getSummaryByEvent();
      expect(byEvent['rpc:response']?.totalMessages, equals(1));
      expect(byEvent['rpc:request']?.totalMessages, equals(1));
    });

    test('should return recent series with max points', () {
      for (var i = 0; i < 10; i++) {
        collector.record(
          ProtocolMetrics(
            timestamp: DateTime.now(),
            protocol: 'jsonrpc-v2',
            encoding: 'json',
            compression: 'none',
            originalSize: 10 + i,
            compressedSize: 10 + i,
            direction: 'send',
            eventName: 'rpc:response',
          ),
        );
      }

      final recent = collector.getRecentSeries(maxPoints: 3);
      expect(recent.length, equals(3));
      expect(recent.first.originalSize, equals(17));
      expect(recent.last.originalSize, equals(19));
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
          eventName: 'rpc:response',
        ),
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          originalSize: 2000,
          compressedSize: 1000,
          direction: 'receive',
          eventName: 'rpc:request',
        ),
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
          originalSize: 500,
          compressedSize: 500,
          direction: 'send',
          eventName: 'rpc:response',
        ),
      ];

      final summary = ProtocolMetricsSummary.fromList(metrics);

      expect(summary.totalMessages, equals(3));
      expect(summary.totalOriginalBytes, equals(3500));
      expect(summary.totalCompressedBytes, equals(2000));
      expect(summary.totalBytesSaved, equals(1500));
      expect(summary.successCount, equals(3));
      expect(summary.protocolUsage['jsonrpc-v2'], equals(3));
      expect(summary.compressionUsage['gzip'], equals(2));
      expect(summary.compressionUsage['none'], equals(1));
      expect(summary.eventUsage['rpc:response'], equals(2));
      expect(summary.eventUsage['rpc:request'], equals(1));
    });

    test('should aggregate durations and isolate usage', () {
      final metrics = [
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          requestedCompression: 'auto',
          originalSize: 1000,
          compressedSize: 400,
          direction: 'send',
          totalDurationUs: 2000,
          encodeDurationUs: 500,
          compressDurationUs: 1200,
          usedIsolate: true,
          usedGzipCompressIsolate: true,
        ),
        ProtocolMetrics(
          timestamp: DateTime.now(),
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
          requestedCompression: 'auto',
          originalSize: 1000,
          compressedSize: 1000,
          direction: 'receive',
          totalDurationUs: 1500,
          decodeDurationUs: 700,
          usedIsolate: true,
          usedJsonDecodeIsolate: true,
        ),
      ];

      final summary = ProtocolMetricsSummary.fromList(metrics);

      expect(summary.requestedCompressionUsage['auto'], equals(2));
      expect(summary.averageTotalDurationUs, equals(1750));
      expect(summary.averageEncodeDurationUs, equals(500));
      expect(summary.averageCompressDurationUs, equals(1200));
      expect(summary.averageDecodeDurationUs, equals(700));
      expect(summary.totalIsolateOperations, equals(2));
      expect(summary.gzipCompressIsolateOperations, equals(1));
      expect(summary.jsonDecodeIsolateOperations, equals(1));
      expect(summary.successRate, equals(1));
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
      expect(summary.successRate, equals(0.0));
    });
  });
}
