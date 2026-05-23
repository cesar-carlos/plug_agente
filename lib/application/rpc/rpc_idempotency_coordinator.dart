import 'package:plug_agente/domain/protocol/protocol.dart';

/// Serializes in-flight RPC executions keyed by namespaced idempotency store keys.
///
/// Prevents duplicate side effects when parallel batch dispatch (or concurrent
/// single requests) reuse the same `{method}:{idempotency_key}` before the cache
/// entry is persisted.
class RpcIdempotencyCoordinator {
  final Map<String, Future<RpcResponse>> _inFlightByKey = <String, Future<RpcResponse>>{};

  /// Runs [action] exclusively for [namespacedKey], or awaits an in-flight leader.
  Future<RpcResponse> runExclusive({
    required String namespacedKey,
    required Future<RpcResponse> Function() action,
  }) {
    final existing = _inFlightByKey[namespacedKey];
    if (existing != null) {
      return existing;
    }

    late Future<RpcResponse> leader;
    leader = () async {
      try {
        return await action();
      } finally {
        if (identical(_inFlightByKey[namespacedKey], leader)) {
          _inFlightByKey.remove(namespacedKey);
        }
      }
    }();

    _inFlightByKey[namespacedKey] = leader;
    return leader;
  }

  RpcResponse remapResponseId(RpcResponse response, Object? requestId) {
    return RpcResponse(
      jsonrpc: response.jsonrpc,
      id: requestId,
      result: response.result,
      error: response.error,
      apiVersion: response.apiVersion,
      meta: response.meta,
    );
  }
}
