import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/authorization_metric.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';

/// Collects authorization metrics for observability.
class AuthorizationMetricsCollector implements IAuthorizationMetricsCollector {
  AuthorizationMetricsCollector();

  final List<AuthorizationMetric> _metrics = [];
  final StreamController<void> _updates = StreamController<void>.broadcast(sync: true);

  List<AuthorizationMetric> get metrics => List.unmodifiable(_metrics);

  @override
  Stream<void> get updates => _updates.stream;

  @override
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

  @override
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

  @override
  AuthorizationMetricsSummary getSummary({Duration? period}) {
    final cutoff = period != null ? DateTime.now().subtract(period) : null;
    final filtered = cutoff != null ? _metrics.where((m) => m.timestamp.isAfter(cutoff)).toList() : _metrics;
    return AuthorizationMetricsSummary.fromList(filtered);
  }

  void _add(AuthorizationMetric metric) {
    _metrics.add(metric);
    const maxMetrics = 1000;
    if (_metrics.length > maxMetrics) {
      _metrics.removeAt(0);
    }
    if (!_updates.isClosed) {
      _updates.add(null);
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
    if (!_updates.isClosed) {
      _updates.add(null);
    }
  }
}
