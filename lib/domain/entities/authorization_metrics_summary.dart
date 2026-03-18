import 'package:plug_agente/domain/entities/authorization_metric.dart';

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
