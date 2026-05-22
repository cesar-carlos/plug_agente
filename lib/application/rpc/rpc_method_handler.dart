import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

class RpcDispatchContext {
  const RpcDispatchContext({
    required this.agentId,
    required this.clientToken,
    required this.streamEmitter,
    required this.limits,
    required this.negotiatedExtensions,
  });

  final String agentId;
  final String? clientToken;
  final IRpcStreamEmitter? streamEmitter;
  final TransportLimits limits;
  final Map<String, dynamic> negotiatedExtensions;
}

abstract class RpcMethodHandler {
  String get method;

  Future<RpcResponse> handle(
    RpcRequest request,
    RpcDispatchContext context,
  );
}
