import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/domain/protocol/rpc_wire_ack_id.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';

void main() {
  group('resolveRpcWireAckId', () {
    test('prefers meta.request_id over body.id', () {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'client-request-id',
        meta: RpcProtocolMeta(requestId: 'hub-wire-id'),
      );

      expect(resolveRpcWireAckId(request), 'hub-wire-id');
    });
  });

  group('RpcRequestGuard replay key', () {
    test('indexes replay by hub wire id when meta.request_id is present', () {
      final guard = RpcRequestGuard();
      const first = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'client-a',
        meta: RpcProtocolMeta(requestId: 'hub-a'),
      );
      const replay = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'client-b',
        meta: RpcProtocolMeta(requestId: 'hub-a'),
      );

      expect(guard.evaluate(first), RpcRequestGuardResult.allow);
      expect(guard.evaluate(replay), RpcRequestGuardResult.replayDetected);
    });
  });
}
