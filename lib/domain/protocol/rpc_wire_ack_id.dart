import 'package:plug_agente/domain/protocol/rpc_request.dart';

/// Resolves the wire-level correlator used for `rpc:request_ack` / `rpc:batch_ack`.
///
/// The hub indexes ack routes by its internal UUID (`meta.request_id`), which may
/// differ from JSON-RPC `body.id` when `clientRequestIdEcho` is negotiated.
String? resolveRpcWireAckId(RpcRequest request) {
  final wireId = request.meta?.requestId;
  if (wireId != null && wireId.trim().isNotEmpty) {
    return wireId;
  }
  final bodyId = request.id;
  if (bodyId == null) {
    return null;
  }
  return bodyId.toString();
}

/// Replay-detection key: prefer the hub wire correlator when present so consumer
/// controlled `body.id` values cannot trip the guard under `clientRequestIdEcho`.
String? resolveRpcReplayGuardKey(RpcRequest request) => resolveRpcWireAckId(request);
