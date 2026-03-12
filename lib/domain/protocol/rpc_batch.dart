import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';

/// JSON-RPC 2.0 Batch request.
///
/// An array of RPC requests to be processed together.
class RpcBatchRequest {
  const RpcBatchRequest(this.requests);

  factory RpcBatchRequest.fromJson(List<dynamic> json) {
    return RpcBatchRequest(
      json.map((e) => RpcRequest.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  final List<RpcRequest> requests;

  List<dynamic> toJson() {
    return requests.map((r) => r.toJson()).toList();
  }

  bool get isEmpty => requests.isEmpty;
  int get length => requests.length;
}

/// JSON-RPC 2.0 Batch response.
///
/// An array of RPC responses corresponding to batch requests.
/// Notifications do not have responses.
class RpcBatchResponse {
  const RpcBatchResponse(this.responses);

  factory RpcBatchResponse.fromJson(List<dynamic> json) {
    return RpcBatchResponse(
      json.map((e) => RpcResponse.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  final List<RpcResponse> responses;

  List<dynamic> toJson() {
    return responses.map((r) => r.toJson()).toList();
  }

  bool get isEmpty => responses.isEmpty;
  int get length => responses.length;
}
