import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';

/// Maximum number of requests allowed in a single batch.
const int rpcBatchMaxSize = 32;

/// Result of batch validation (strict mode).
sealed class RpcBatchValidationResult {
  const RpcBatchValidationResult();
}

/// Batch is valid.
class RpcBatchValid extends RpcBatchValidationResult {
  const RpcBatchValid();
}

/// Batch has duplicate request IDs.
class RpcBatchDuplicateIds extends RpcBatchValidationResult {
  const RpcBatchDuplicateIds(this.duplicateIds);
  final List<dynamic> duplicateIds;
}

/// Batch exceeds size limit.
class RpcBatchExceedsLimit extends RpcBatchValidationResult {
  const RpcBatchExceedsLimit(this.size, this.limit);
  final int size;
  final int limit;
}

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

  /// Validates batch for strict mode: unique IDs and size limit.
  RpcBatchValidationResult validateStrict() {
    if (requests.length > rpcBatchMaxSize) {
      return RpcBatchExceedsLimit(requests.length, rpcBatchMaxSize);
    }

    final seenIds = <String>{};
    final duplicateIds = <dynamic>[];

    for (final req in requests) {
      if (req.id == null) continue;
      final idStr = req.id.toString();
      if (seenIds.contains(idStr)) {
        if (!duplicateIds.contains(req.id)) {
          duplicateIds.add(req.id);
        }
      } else {
        seenIds.add(idStr);
      }
    }

    if (duplicateIds.isNotEmpty) {
      return RpcBatchDuplicateIds(duplicateIds);
    }

    return const RpcBatchValid();
  }
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
