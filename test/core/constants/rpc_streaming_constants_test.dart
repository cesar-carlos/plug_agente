import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';

void main() {
  group('RpcStreamingConstants', () {
    test('backpressure reason should be non-empty', () {
      expect(RpcStreamingConstants.backpressureOverflowReason, isNotEmpty);
    });
  });
}
