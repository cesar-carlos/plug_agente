import 'dart:developer' as developer;

/// Single authorization decision record.
class AuthorizationMetric {
  const AuthorizationMetric({
    required this.timestamp,
    required this.authorized,
    this.clientId,
    this.operation,
    this.resource,
    this.reason,
  });

  final DateTime timestamp;
  final bool authorized;
  final String? clientId;
  final String? operation;
  final String? resource;
  final String? reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'authorized': authorized,
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
  });

  factory AuthorizationMetricsSummary.fromList(List<AuthorizationMetric> metrics) {
    var authorized = 0;
    var denied = 0;
    final byOperation = <String, int>{};
    final byResource = <String, int>{};
    final byReason = <String, int>{};

    for (final m in metrics) {
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

    return AuthorizationMetricsSummary(
      totalAuthorized: authorized,
      totalDenied: denied,
      deniedByOperation: byOperation,
      deniedByResource: byResource,
      deniedByReason: byReason,
    );
  }

  final int totalAuthorized;
  final int totalDenied;
  final Map<String, int> deniedByOperation;
  final Map<String, int> deniedByResource;
  final Map<String, int> deniedByReason;

  int get total => totalAuthorized + totalDenied;

  double get denialRate => total > 0 ? totalDenied / total : 0.0;
}

/// Collects authorization metrics for observability.
class AuthorizationMetricsCollector {
  AuthorizationMetricsCollector();

  final List<AuthorizationMetric> _metrics = [];

  List<AuthorizationMetric> get metrics => List.unmodifiable(_metrics);

  void recordAuthorized({
    String? clientId,
    String? operation,
    String? resource,
  }) {
    final metric = AuthorizationMetric(
      timestamp: DateTime.now(),
      authorized: true,
      clientId: clientId,
      operation: operation,
      resource: resource,
    );
    _add(metric);
  }

  void recordDenied({
    String? clientId,
    String? operation,
    String? resource,
    String? reason,
  }) {
    final metric = AuthorizationMetric(
      timestamp: DateTime.now(),
      authorized: false,
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
      'operation: ${metric.operation ?? "?"}',
      'resource: ${metric.resource ?? "?"}',
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
