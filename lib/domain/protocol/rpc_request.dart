// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// JSON-RPC 2.0 Request object.
///
/// Represents a remote procedure call request following the JSON-RPC 2.0 specification.
class RpcRequest {
  const RpcRequest({
    required this.jsonrpc,
    required this.method,
    required this.id,
    this.params,
  });

  factory RpcRequest.fromJson(Map<String, dynamic> json) {
    return RpcRequest(
      jsonrpc: json['jsonrpc'] as String,
      method: json['method'] as String,
      id: json['id'],
      params: json['params'],
    );
  }

  /// JSON-RPC version. Must be exactly "2.0".
  final String jsonrpc;

  /// The method to be invoked.
  final String method;

  /// Request identifier. Can be String, Number, or null.
  /// Used to correlate request with response.
  final dynamic id;

  /// Method parameters. Can be Object or Array.
  final dynamic params;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'method': method,
      'id': id,
    };

    if (params != null) {
      json['params'] = params;
    }

    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RpcRequest && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// JSON-RPC 2.0 Notification (request without id).
class RpcNotification {
  const RpcNotification({
    required this.jsonrpc,
    required this.method,
    this.params,
  });

  factory RpcNotification.fromJson(Map<String, dynamic> json) {
    return RpcNotification(
      jsonrpc: json['jsonrpc'] as String,
      method: json['method'] as String,
      params: json['params'],
    );
  }

  final String jsonrpc;
  final String method;
  final dynamic params;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'method': method,
    };

    if (params != null) {
      json['params'] = params;
    }

    return json;
  }
}
