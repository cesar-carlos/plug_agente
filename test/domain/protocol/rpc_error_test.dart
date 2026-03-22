import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';

void main() {
  group('RpcError', () {
    test('toString includes code and message', () {
      const err = RpcError(code: -32600, message: 'Invalid Request');
      expect(
        err.toString(),
        'RpcError(code: -32600, message: Invalid Request)',
      );
    });

    test('toString includes data when present', () {
      const err = RpcError(
        code: 1,
        message: 'x',
        data: <String, Object?>{'hint': 'y'},
      );
      expect(
        err.toString(),
        'RpcError(code: 1, message: x, data: {hint: y})',
      );
    });
  });
}
