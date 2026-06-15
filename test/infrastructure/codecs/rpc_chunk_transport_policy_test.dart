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
  });
}
