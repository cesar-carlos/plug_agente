import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

void main() {
  group('TransportLimits', () {
    test('default constructor should use default values', () {
      const limits = TransportLimits();

      check(
        limits.maxPayloadBytes,
      ).equals(TransportLimits.defaultMaxPayloadBytes);
      check(limits.maxRows).equals(TransportLimits.defaultMaxRows);
      check(limits.maxBatchSize).equals(TransportLimits.defaultMaxBatchSize);
      check(
        limits.maxConcurrentStreams,
      ).equals(TransportLimits.defaultMaxConcurrentStreams);
      check(
        limits.streamingChunkSize,
      ).equals(TransportLimits.defaultStreamingChunkSize);
      check(
        limits.streamingRowThreshold,
      ).equals(TransportLimits.defaultStreamingRowThreshold);
    });

    test('fromJson should parse all fields', () {
      final json = {
        'max_payload_bytes': 5 * 1024 * 1024,
        'max_rows': 10000,
        'max_batch_size': 16,
        'max_concurrent_streams': 4,
        'streaming_chunk_size': 250,
        'streaming_row_threshold': 750,
      };

      final limits = TransportLimits.fromJson(json);

      check(limits.maxPayloadBytes).equals(5 * 1024 * 1024);
      check(limits.maxRows).equals(10000);
      check(limits.maxBatchSize).equals(16);
      check(limits.maxConcurrentStreams).equals(4);
      check(limits.streamingChunkSize).equals(250);
      check(limits.streamingRowThreshold).equals(750);
    });

    test('fromJson should use defaults for missing fields', () {
      final limits = TransportLimits.fromJson({});

      check(
        limits.maxPayloadBytes,
      ).equals(TransportLimits.defaultMaxPayloadBytes);
      check(limits.maxRows).equals(TransportLimits.defaultMaxRows);
    });

    test('toJson should serialize all fields', () {
      const limits = TransportLimits(
        maxPayloadBytes: 1024,
        maxRows: 100,
        maxBatchSize: 8,
        maxConcurrentStreams: 2,
        streamingChunkSize: 50,
        streamingRowThreshold: 75,
      );

      final json = limits.toJson();

      check(json['max_payload_bytes']).equals(1024);
      check(json['max_rows']).equals(100);
      check(json['max_batch_size']).equals(8);
      check(json['max_concurrent_streams']).equals(2);
      check(json['streaming_chunk_size']).equals(50);
      check(json['streaming_row_threshold']).equals(75);
    });

    test('negotiateWith should pick the minimum of each field', () {
      const agent = TransportLimits(
        maxRows: 30000,
        maxConcurrentStreams: 4,
        streamingChunkSize: 250,
        streamingRowThreshold: 900,
      );
      const server = TransportLimits(
        maxPayloadBytes: 5 * 1024 * 1024,
        maxRows: 100000,
        maxBatchSize: 16,
        maxConcurrentStreams: 2,
        streamingChunkSize: 100,
      );

      final effective = agent.negotiateWith(server);

      check(effective.maxPayloadBytes).equals(5 * 1024 * 1024);
      check(effective.maxRows).equals(30000);
      check(effective.maxBatchSize).equals(16);
      check(effective.maxConcurrentStreams).equals(2);
      check(effective.streamingChunkSize).equals(100);
      check(effective.streamingRowThreshold).equals(500);
    });

    test('negotiateWith symmetric - same result regardless of order', () {
      const a = TransportLimits(
        maxRows: 100,
        maxBatchSize: 10,
        streamingChunkSize: 120,
      );
      const b = TransportLimits(
        maxRows: 200,
        maxBatchSize: 5,
        streamingChunkSize: 80,
      );

      final ab = a.negotiateWith(b);
      final ba = b.negotiateWith(a);

      check(ab.maxRows).equals(ba.maxRows);
      check(ab.maxBatchSize).equals(ba.maxBatchSize);
      check(ab.streamingChunkSize).equals(ba.streamingChunkSize);
    });
  });

  group('ProtocolCapabilities with limits', () {
    test('toJson should include limits', () {
      final caps = ProtocolCapabilities.defaultCapabilities();
      final json = caps.toJson();

      check(json.containsKey('limits')).isTrue();
      check(
        (json['limits'] as Map<String, dynamic>)['max_batch_size'],
      ).equals(TransportLimits.defaultMaxBatchSize);
    });

    test('fromJson should parse limits', () {
      final json = {
        'protocols': ['jsonrpc-v2'],
        'encodings': ['json'],
        'compressions': ['none'],
        'limits': {
          'max_rows': 999,
          'max_batch_size': 8,
        },
      };

      final caps = ProtocolCapabilities.fromJson(json);

      check(caps.limits.maxRows).equals(999);
      check(caps.limits.maxBatchSize).equals(8);
    });

    test('fromJson without limits should use defaults', () {
      final json = {
        'protocols': ['jsonrpc-v2'],
        'encodings': ['json'],
        'compressions': ['none'],
      };

      final caps = ProtocolCapabilities.fromJson(json);

      check(
        caps.limits.maxPayloadBytes,
      ).equals(TransportLimits.defaultMaxPayloadBytes);
    });
  });
}
