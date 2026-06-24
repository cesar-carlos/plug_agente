/// Protocol metadata for RPC v2.1 (trace, request, agent, timestamp).
class RpcProtocolMeta {
  const RpcProtocolMeta({
    this.traceId,
    this.traceParent,
    this.traceState,
    this.requestId,
    this.agentId,
    this.timestamp,
    this.requestServerTimings,
    this.agentPhases,
    this.healthSnapshot,
  });

  factory RpcProtocolMeta.fromJson(Map<String, dynamic> json) {
    return RpcProtocolMeta(
      traceId: json['trace_id'] as String?,
      traceParent: json['traceparent'] as String?,
      traceState: json['tracestate'] as String?,
      requestId: json['request_id'] as String?,
      agentId: json['agent_id'] as String?,
      timestamp: json['timestamp'] as String?,
      requestServerTimings: json['requestServerTimings'] as bool?,
      agentPhases: _readPhaseMap(json['agent_phases']),
      healthSnapshot: _readObjectMap(json['health_snapshot']),
    );
  }

  final String? traceId;
  final String? traceParent;
  final String? traceState;
  final String? requestId;
  final String? agentId;
  final String? timestamp;

  /// Hub opt-in for server-side phase diagnostics (request-only).
  final bool? requestServerTimings;

  /// Per-phase agent timings in milliseconds (response-only, ADR 0010).
  final Map<String, double>? agentPhases;

  /// Compact health snapshot piggybacked on unary responses (ADR 0011).
  final Map<String, Object?>? healthSnapshot;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (traceId != null) json['trace_id'] = traceId;
    if (traceParent != null) json['traceparent'] = traceParent;
    if (traceState != null) json['tracestate'] = traceState;
    if (requestId != null) json['request_id'] = requestId;
    if (agentId != null) json['agent_id'] = agentId;
    if (timestamp != null) json['timestamp'] = timestamp;
    if (agentPhases != null && agentPhases!.isNotEmpty) {
      json['agent_phases'] = agentPhases;
    }
    if (healthSnapshot != null && healthSnapshot!.isNotEmpty) {
      json['health_snapshot'] = healthSnapshot;
    }
    return json;
  }

  static Map<String, double>? _readPhaseMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final phases = <String, double>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is num) {
        phases[entry.key.toString()] = value.toDouble();
      }
    }
    return phases.isEmpty ? null : phases;
  }

  static Map<String, Object?>? _readObjectMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return Map<String, Object?>.from(raw);
  }
}
