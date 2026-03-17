import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';

void main() {
  group('RpcProtocolMeta', () {
    test('should parse from json', () {
      final json = <String, dynamic>{
        'trace_id': 't-1',
        'traceparent':
            '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        'tracestate': 'vendor=value',
        'request_id': 'r-1',
        'agent_id': 'a-1',
        'timestamp': '2026-03-12T10:00:00Z',
      };

      final meta = RpcProtocolMeta.fromJson(json);

      expect(meta.traceId, equals('t-1'));
      expect(
        meta.traceParent,
        equals('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'),
      );
      expect(meta.traceState, equals('vendor=value'));
      expect(meta.requestId, equals('r-1'));
      expect(meta.agentId, equals('a-1'));
      expect(meta.timestamp, equals('2026-03-12T10:00:00Z'));
    });

    test('should serialize to json only non-null fields', () {
      const meta = RpcProtocolMeta(
        traceId: 't-1',
        traceParent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        agentId: 'a-1',
      );

      final json = meta.toJson();

      expect(json, containsPair('trace_id', 't-1'));
      expect(
        json,
        containsPair(
          'traceparent',
          '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        ),
      );
      expect(json, containsPair('agent_id', 'a-1'));
      expect(json, isNot(contains('request_id')));
      expect(json, isNot(contains('timestamp')));
    });
  });
}
