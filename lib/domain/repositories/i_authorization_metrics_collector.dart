import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';

abstract class IAuthorizationMetricsCollector {
  AuthorizationMetricsSummary getSummary({Duration? period});

  void recordAuthorized({
    String? requestId,
    String? method,
    int? latencyMs,
    String? clientId,
    String? operation,
    String? resource,
  });

  void recordDenied({
    String? requestId,
    String? method,
    int? latencyMs,
    String? clientId,
    String? operation,
    String? resource,
    String? reason,
  });
}
