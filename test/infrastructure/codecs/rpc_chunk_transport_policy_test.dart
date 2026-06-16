import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_chunk_transport_policy.dart';

void main() {
  group('RpcChunkTransportPolicy', () {
    test('uses dedicated thresholds for rpc:chunk events', () {
      expect(RpcChunkTransportPolicy.isRpcChunkEvent('rpc:chunk'), isTrue);
      expect(RpcChunkTransportPolicy.isRpcChunkEvent('rpc:response'), isFalse);

      final chunkJsonThreshold = RpcChunkTransportPolicy.jsonEncodeIsolateThresholdBytes('rpc:chunk');
      final responseJsonThreshold = RpcChunkTransportPolicy.jsonEncodeIsolateThresholdBytes('rpc:response');
      expect(chunkJsonThreshold, lessThan(responseJsonThreshold));

      final chunkCompression = RpcChunkTransportPolicy.compressionThresholdBytes(
        'rpc:chunk',
        defaultThreshold: 4096,
      );
      expect(chunkCompression, lessThan(4096));
    });

    test('skips gzip for columnar rpc:chunk payloads by default', () {
      final payload = <String, dynamic>{
        'columnar': <String, dynamic>{'row_count': 1, 'columns': <dynamic>[]},
      };

      expect(
        RpcChunkTransportPolicy.shouldCompressPayload(
          compressionMode: 'auto',
          originalSize: 4096,
          compressionThreshold: 1024,
          metricEventName: 'rpc:chunk',
          payload: payload,
        ),
        isFalse,
      );
      expect(
        RpcChunkTransportPolicy.shouldCompressPayload(
          compressionMode: 'auto',
          originalSize: 4096,
          compressionThreshold: 1024,
          metricEventName: 'rpc:response',
          payload: payload,
        ),
        isTrue,
      );
    });
  });
}
