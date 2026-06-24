import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';
import 'package:plug_agente/domain/protocol/transport_extension_negotiation.dart';
import 'package:plug_agente/infrastructure/external_services/transport/agent_latency_trace.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_response_enricher.dart';

void main() {
  group('RpcInboundResponseEnricher', () {
    const negotiated = <String, dynamic>{
      TransportExtensionNegotiation.agentPhaseTimings:
          TransportExtensionNegotiation.agentPhaseTimingsVersion,
    };

    test('attaches agent_phases when consumer opted into server timings', () {
      final enricher = RpcInboundResponseEnricher();
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'client-1',
        meta: RpcProtocolMeta(
          requestId: 'hub-1',
          requestServerTimings: true,
        ),
      );
      final response = RpcResponse.success(
        id: 'client-1',
        result: const <String, dynamic>{'ok': true},
        meta: const RpcProtocolMeta(requestId: 'hub-1'),
      );
      final trace = AgentLatencyTrace()
        ..markFrameDecodeComplete()
        ..markDispatchStarted()
        ..markDispatchComplete(isSqlMethod: true);

      final enriched = enricher.enrichUnaryResponse(
        request: request,
        response: response,
        negotiatedExtensions: negotiated,
        latencyTrace: trace,
      );

      expect(enriched.meta?.agentPhases, isNotNull);
      expect(enriched.meta?.agentPhases?['frame_decode_ms'], isA<double>());
      expect(enriched.meta?.agentPhases?['sql_execute_ms'], isA<double>());
    });

    test('skips agent_phases when requestServerTimings is absent', () {
      final enricher = RpcInboundResponseEnricher();
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'client-1',
        meta: RpcProtocolMeta(requestId: 'hub-1'),
      );
      final response = RpcResponse.success(
        id: 'client-1',
        result: const <String, dynamic>{'ok': true},
      );

      final enriched = enricher.enrichUnaryResponse(
        request: request,
        response: response,
        negotiatedExtensions: negotiated,
        latencyTrace: AgentLatencyTrace()..markFrameDecodeComplete(),
      );

      expect(enriched.meta?.agentPhases, isNull);
    });
  });
}
