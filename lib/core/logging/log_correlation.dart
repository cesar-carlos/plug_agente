import 'dart:async';

/// Request-scoped identifiers attached to structured logs.
abstract final class LogCorrelation {
  static const _rpcRequestIdKey = #plugLogRpcRequestId;
  static const _rpcMethodKey = #plugLogRpcMethod;

  static String? get rpcRequestId => Zone.current[_rpcRequestIdKey] as String?;

  static String? get rpcMethod => Zone.current[_rpcMethodKey] as String?;

  static Map<String, dynamic> get currentContext {
    final requestId = rpcRequestId;
    final method = rpcMethod;
    return {
      if (requestId != null && requestId.isNotEmpty) 'rpc_request_id': requestId,
      if (method != null && method.isNotEmpty) 'rpc_method': method,
    };
  }

  static Future<T> run<T>({
    required String? rpcRequestId,
    required String? rpcMethod,
    required Future<T> Function() body,
  }) {
    return runZoned(
      body,
      zoneValues: {
        _rpcRequestIdKey: rpcRequestId,
        _rpcMethodKey: rpcMethod,
      },
    );
  }
}
