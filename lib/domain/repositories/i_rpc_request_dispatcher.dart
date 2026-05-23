import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

/// Routes inbound JSON-RPC requests to the appropriate handler implementation.
abstract class IRpcRequestDispatcher {
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  });

  /// Stops any active SQL stream when the hub socket disconnects.
  Future<void> cancelActiveStreamOnDisconnect();
}
