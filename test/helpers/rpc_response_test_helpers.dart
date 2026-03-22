import 'package:plug_agente/domain/protocol/rpc_response.dart';

/// Compact failure description for `expect(..., reason: ...)` on RPC paths.
String describeRpcResponseFailure(RpcResponse response) {
  final err = response.error;
  if (err == null) {
    return 'RpcResponse.success id=${response.id}';
  }
  return 'id=${response.id} $err';
}
