/// Protocol metadata for RPC v2.1 (trace, request, agent, timestamp).
class RpcProtocolMeta {
  const RpcProtocolMeta({
    this.traceId,
    this.requestId,
    this.agentId,
    this.timestamp,
  });

  factory RpcProtocolMeta.fromJson(Map<String, dynamic> json) {
    return RpcProtocolMeta(
      traceId: json['trace_id'] as String?,
      requestId: json['request_id'] as String?,
      agentId: json['agent_id'] as String?,
      timestamp: json['timestamp'] as String?,
    );
  }

  final String? traceId;
  final String? requestId;
  final String? agentId;
  final String? timestamp;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (traceId != null) json['trace_id'] = traceId;
    if (requestId != null) json['request_id'] = requestId;
    if (agentId != null) json['agent_id'] = agentId;
    if (timestamp != null) json['timestamp'] = timestamp;
    return json;
  }
}
