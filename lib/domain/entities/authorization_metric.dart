/// Single authorization decision record.
class AuthorizationMetric {
  const AuthorizationMetric({
    required this.timestamp,
    required this.authorized,
    this.requestId,
    this.method,
    this.latencyMs,
    this.clientId,
    this.operation,
    this.resource,
    this.reason,
  });

  final DateTime timestamp;
  final bool authorized;
  final String? requestId;
  final String? method;
  final int? latencyMs;
  final String? clientId;
  final String? operation;
  final String? resource;
  final String? reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'authorized': authorized,
      if (requestId != null) 'request_id': requestId,
      if (method != null) 'method': method,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (clientId != null) 'client_id': clientId,
      if (operation != null) 'operation': operation,
      if (resource != null) 'resource': resource,
      if (reason != null) 'reason': reason,
    };
  }
}
