// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';

/// JSON-RPC 2.0 Response object.
///
/// Represents a response to a JSON-RPC request.
/// Either `result` or `error` must be present, but not both.
class RpcResponse {
  const RpcResponse({
    required this.jsonrpc,
    required this.id,
    this.result,
    this.error,
    this.apiVersion,
    this.meta,
  }) : assert(
         (result != null && error == null) || (result == null && error != null),
         'Either result or error must be present, but not both',
       );

  factory RpcResponse.success({
    required dynamic id,
    required dynamic result,
    String? apiVersion,
    RpcProtocolMeta? meta,
  }) {
    return RpcResponse(
      jsonrpc: '2.0',
      id: id,
      result: result,
      apiVersion: apiVersion,
      meta: meta,
    );
  }

  factory RpcResponse.error({
    required dynamic id,
    required RpcError error,
    String? apiVersion,
    RpcProtocolMeta? meta,
  }) {
    return RpcResponse(
      jsonrpc: '2.0',
      id: id,
      error: error,
      apiVersion: apiVersion,
      meta: meta,
    );
  }

  factory RpcResponse.fromJson(Map<String, dynamic> json) {
    return RpcResponse(
      jsonrpc: json['jsonrpc'] as String,
      id: json['id'],
      result: json['result'],
      error: json['error'] != null ? RpcError.fromJson(json['error'] as Map<String, dynamic>) : null,
      apiVersion: json['api_version'] as String?,
      meta: json['meta'] != null
          ? RpcProtocolMeta.fromJson(
              json['meta'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// JSON-RPC version. Must be exactly "2.0".
  final String jsonrpc;

  /// Request identifier. Must match the id in the request.
  final dynamic id;

  /// Result on success. Must not exist if there was an error.
  final dynamic result;

  /// Error on failure. Must not exist if there was success.
  final RpcError? error;

  /// API version (v2.1 optional extension).
  final String? apiVersion;

  /// Protocol metadata (v2.1 optional extension).
  final RpcProtocolMeta? meta;

  bool get isSuccess => error == null;
  bool get isError => error != null;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'id': id,
    };

    if (result != null) {
      json['result'] = result;
    }

    if (error != null) {
      json['error'] = error!.toJson();
    }

    if (apiVersion != null) {
      json['api_version'] = apiVersion;
    }
    if (meta != null) {
      json['meta'] = meta!.toJson();
    }

    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RpcResponse && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
