import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';
import 'package:plug_agente/domain/protocol/transport_extension_negotiation.dart';
import 'package:plug_agente/infrastructure/external_services/transport/agent_latency_trace.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_health_piggyback_sampler.dart';

/// Merges optional performance observability fields into unary RPC responses.
final class RpcInboundResponseEnricher {
  RpcInboundResponseEnricher({
    RpcHealthPiggybackSampler? healthPiggybackSampler,
  }) : _healthPiggybackSampler = healthPiggybackSampler;

  final RpcHealthPiggybackSampler? _healthPiggybackSampler;

  RpcResponse enrichUnaryResponse({
    required RpcRequest request,
    required RpcResponse response,
    required Map<String, dynamic> negotiatedExtensions,
    AgentLatencyTrace? latencyTrace,
  }) {
    final requestMeta = request.meta;
    final includePhaseTimings =
        TransportExtensionNegotiation.isAgentPhaseTimingsNegotiated(negotiatedExtensions) &&
        (requestMeta?.requestServerTimings ?? false);
    final phaseTimings = includePhaseTimings ? latencyTrace?.toAgentPhases() : null;
    final healthSnapshot = _healthPiggybackSampler?.maybeSample(negotiatedExtensions);

    if (phaseTimings == null && healthSnapshot == null) {
      return response;
    }

    final existingMeta = response.meta ?? requestMeta;
    final mergedMeta = RpcProtocolMeta(
      traceId: existingMeta?.traceId,
      traceParent: existingMeta?.traceParent,
      traceState: existingMeta?.traceState,
      requestId: existingMeta?.requestId ?? requestMeta?.requestId,
      agentId: existingMeta?.agentId,
      timestamp: existingMeta?.timestamp,
      agentPhases: phaseTimings,
      healthSnapshot: healthSnapshot,
    );

    if (response.isError) {
      return RpcResponse.error(
        id: response.id,
        error: response.error!,
        apiVersion: response.apiVersion,
        meta: mergedMeta,
      );
    }

    return RpcResponse.success(
      id: response.id,
      result: response.result,
      apiVersion: response.apiVersion,
      meta: mergedMeta,
    );
  }
}
