import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';

import 'rpc_response_test_helpers.dart';

void main() {
  group('describeRpcResponseFailure', () {
    test('describes error responses with id', () {
      final resp = RpcResponse.error(
        id: 'r1',
        error: const RpcError(code: -1, message: 'oops'),
      );
      expect(
        describeRpcResponseFailure(resp),
        'id=r1 RpcError(code: -1, message: oops)',
      );
    });

    test('describes unexpected success when error is null', () {
      final resp = RpcResponse.success(id: 'ok', result: true);
      expect(
        describeRpcResponseFailure(resp),
        'RpcResponse.success id=ok',
      );
    });
  });
}
