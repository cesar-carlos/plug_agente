import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

class AuthorizationCacheMetricsCollector implements IAuthorizationCacheMetrics {
  AuthorizationCacheMetricsCollector(this._metrics);

  final MetricsCollector _metrics;

  @override
  void recordDecisionCacheLookup({required bool hit}) {
    if (hit) {
      _metrics.recordAuthDecisionCacheHit();
    } else {
      _metrics.recordAuthDecisionCacheMiss();
    }
  }

  @override
  void recordPolicyCacheLookup({required bool hit}) {
    if (hit) {
      _metrics.recordAuthPolicyCacheHit();
    } else {
      _metrics.recordAuthPolicyCacheMiss();
    }
  }
}
