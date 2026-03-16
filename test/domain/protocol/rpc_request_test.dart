import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';

void main() {
  group('RpcRequest', () {
    test('isNotification should be true when id is null', () {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: null,
        params: <String, dynamic>{},
      );

      expect(request.isNotification, isTrue);
    });

    test('isNotification should be false when id is present', () {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: <String, dynamic>{},
      );

      expect(request.isNotification, isFalse);
    });

    test('fromJson should parse api_version and meta when present', () {
      final json = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': 'req-1',
        'params': <String, dynamic>{},
        'api_version': '2.1',
        'meta': <String, dynamic>{
          'trace_id': 't-1',
          'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
          'agent_id': 'a-1',
        },
      };

      final request = RpcRequest.fromJson(json);

      expect(request.apiVersion, equals('2.1'));
      expect(request.meta?.traceId, equals('t-1'));
      expect(
        request.meta?.traceParent,
        equals('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'),
      );
      expect(request.meta?.agentId, equals('a-1'));
    });
  });
}
