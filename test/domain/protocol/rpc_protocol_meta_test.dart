import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';

void main() {
  group('RpcProtocolMeta', () {
    test('should parse from json', () {
      final json = <String, dynamic>{
        'trace_id': 't-1',
        'request_id': 'r-1',
        'agent_id': 'a-1',
        'timestamp': '2026-03-12T10:00:00Z',
      };

      final meta = RpcProtocolMeta.fromJson(json);

      expect(meta.traceId, equals('t-1'));
      expect(meta.requestId, equals('r-1'));
      expect(meta.agentId, equals('a-1'));
      expect(meta.timestamp, equals('2026-03-12T10:00:00Z'));
    });

    test('should serialize to json only non-null fields', () {
      const meta = RpcProtocolMeta(
        traceId: 't-1',
        agentId: 'a-1',
      );

      final json = meta.toJson();

      expect(json, containsPair('trace_id', 't-1'));
      expect(json, containsPair('agent_id', 'a-1'));
      expect(json, isNot(contains('request_id')));
      expect(json, isNot(contains('timestamp')));
    });
  });
}
