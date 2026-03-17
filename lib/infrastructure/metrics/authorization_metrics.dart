import 'dart:developer' as developer;

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

/// Summary of authorization metrics.
class AuthorizationMetricsSummary {
  const AuthorizationMetricsSummary({
    required this.totalAuthorized,
    required this.totalDenied,
    required this.deniedByOperation,
    required this.deniedByResource,
    required this.deniedByReason,
    required this.p95LatencyByMethodMs,
    required this.p99LatencyByMethodMs,
  });

  factory AuthorizationMetricsSummary.fromList(
    List<AuthorizationMetric> metrics,
  ) {
    var authorized = 0;
    var denied = 0;
    final byOperation = <String, int>{};
    final byResource = <String, int>{};
    final byReason = <String, int>{};
    final latencyByMethod = <String, List<int>>{};

    for (final m in metrics) {
      if (m.method != null && m.latencyMs != null) {
        latencyByMethod.putIfAbsent(m.method!, () => <int>[]).add(m.latencyMs!);
      }
      if (m.authorized) {
        authorized++;
      } else {
        denied++;
        if (m.operation != null) {
          byOperation[m.operation!] = (byOperation[m.operation!] ?? 0) + 1;
        }
        if (m.resource != null) {
          byResource[m.resource!] = (byResource[m.resource!] ?? 0) + 1;
        }
        if (m.reason != null) {
          byReason[m.reason!] = (byReason[m.reason!] ?? 0) + 1;
        }
      }
    }

    final p95ByMethod = <String, int>{};
    final p99ByMethod = <String, int>{};
    for (final entry in latencyByMethod.entries) {
      final sorted = List<int>.from(entry.value)..sort();
      p95ByMethod[entry.key] = _percentile(sorted, 0.95);
      p99ByMethod[entry.key] = _percentile(sorted, 0.99);
    }

    return AuthorizationMetricsSummary(
      totalAuthorized: authorized,
      totalDenied: denied,
      deniedByOperation: byOperation,
      deniedByResource: byResource,
      deniedByReason: byReason,
      p95LatencyByMethodMs: p95ByMethod,
      p99LatencyByMethodMs: p99ByMethod,
    );
  }

  final int totalAuthorized;
  final int totalDenied;
  final Map<String, int> deniedByOperation;
  final Map<String, int> deniedByResource;
  final Map<String, int> deniedByReason;
  final Map<String, int> p95LatencyByMethodMs;
  final Map<String, int> p99LatencyByMethodMs;

  int get total => totalAuthorized + totalDenied;

  double get denialRate => total > 0 ? totalDenied / total : 0.0;

  int get overallP95LatencyMs {
    if (p95LatencyByMethodMs.isEmpty) {
      return 0;
    }
    return p95LatencyByMethodMs.values.reduce((a, b) => a > b ? a : b);
  }

  int get overallP99LatencyMs {
    if (p99LatencyByMethodMs.isEmpty) {
      return 0;
    }
    return p99LatencyByMethodMs.values.reduce((a, b) => a > b ? a : b);
  }

  double reasonRate(String reason) {
    if (totalDenied == 0) {
      return 0;
    }
    final count = deniedByReason[reason] ?? 0;
    return count / totalDenied;
  }

  static int _percentile(List<int> sorted, double percentile) {
    if (sorted.isEmpty) {
      return 0;
    }
    final index = (percentile * (sorted.length - 1)).ceil();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}

/// Collects authorization metrics for observability.
class AuthorizationMetricsCollector {
  AuthorizationMetricsCollector();

  final List<AuthorizationMetric> _metrics = [];

  List<AuthorizationMetric> get metrics => List.unmodifiable(_metrics);

  void recordAuthorized({
    String? requestId,
    String? method,
    int? latencyMs,
    String? clientId,
    String? operation,
    String? resource,
  }) {
    final metric = AuthorizationMetric(
      timestamp: DateTime.now(),
      authorized: true,
      requestId: requestId,
      method: method,
      latencyMs: latencyMs,
      clientId: clientId,
      operation: operation,
      resource: resource,
    );
    _add(metric);
  }

  void recordDenied({
    String? requestId,
    String? method,
    int? latencyMs,
    String? clientId,
    String? operation,
    String? resource,
    String? reason,
  }) {
    final metric = AuthorizationMetric(
      timestamp: DateTime.now(),
      authorized: false,
      requestId: requestId,
      method: method,
      latencyMs: latencyMs,
      clientId: clientId,
      operation: operation,
      resource: resource,
      reason: reason,
    );
    _add(metric);
    _logDenial(metric);
  }

  void _add(AuthorizationMetric metric) {
    _metrics.add(metric);
    const maxMetrics = 1000;
    if (_metrics.length > maxMetrics) {
      _metrics.removeAt(0);
    }
  }

  void _logDenial(AuthorizationMetric metric) {
    final parts = <String>[
      'client_id: ${metric.clientId ?? "?"}',
      'request_id: ${metric.requestId ?? "?"}',
      'method: ${metric.method ?? "?"}',
      'operation: ${metric.operation ?? "?"}',
      'resource: ${metric.resource ?? "?"}',
      if (metric.latencyMs != null) 'latency_ms: ${metric.latencyMs}',
      if (metric.reason != null) 'reason: ${metric.reason}',
    ];
    developer.log(
      'Authorization denied | ${parts.join(", ")}',
      name: 'auth',
      time: metric.timestamp,
      level: 900,
    );
  }

  void clear() {
    _metrics.clear();
  }

  AuthorizationMetricsSummary getSummary({Duration? period}) {
    final cutoff = period != null ? DateTime.now().subtract(period) : null;
    final filtered = cutoff != null
        ? _metrics.where((m) => m.timestamp.isAfter(cutoff)).toList()
        : _metrics;
    return AuthorizationMetricsSummary.fromList(filtered);
  }
}
