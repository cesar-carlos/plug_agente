part of 'metrics_collector.dart';

/// Client-token authorization cache and policy metrics.
base mixin MetricsCollectorAuthDomain on MetricsCollectorCore {
  int get authDecisionCacheHitCount => _eventCounters[MetricsCollectorCore.authDecisionCacheHitCounter] ?? 0;
  int get authDecisionCacheMissCount => _eventCounters[MetricsCollectorCore.authDecisionCacheMissCounter] ?? 0;
  int get authPolicyCacheHitCount => _eventCounters[MetricsCollectorCore.authPolicyCacheHitCounter] ?? 0;
  int get authPolicyCacheMissCount => _eventCounters[MetricsCollectorCore.authPolicyCacheMissCounter] ?? 0;
  int get rpcClientTokenGetPolicySuccessCount => _eventCounters[MetricsCollectorCore.rpcClientTokenGetPolicySuccessCounter] ?? 0;
  int get rpcClientTokenGetPolicyFailureCount => _eventCounters[MetricsCollectorCore.rpcClientTokenGetPolicyFailureCounter] ?? 0;
  int get rpcClientTokenGetPolicyRateLimitedCount => _eventCounters[MetricsCollectorCore.rpcClientTokenGetPolicyRateLimitedCounter] ?? 0;

  void recordAuthDecisionCacheHit() => _incrementEventCounter(MetricsCollectorCore.authDecisionCacheHitCounter);

  void recordAuthDecisionCacheMiss() => _incrementEventCounter(MetricsCollectorCore.authDecisionCacheMissCounter);

  void recordAuthPolicyCacheHit() => _incrementEventCounter(MetricsCollectorCore.authPolicyCacheHitCounter);

  void recordAuthPolicyCacheMiss() => _incrementEventCounter(MetricsCollectorCore.authPolicyCacheMissCounter);

  void recordClientTokenGetPolicySuccess() => _incrementEventCounter(MetricsCollectorCore.rpcClientTokenGetPolicySuccessCounter);

  void recordClientTokenGetPolicyFailure(Failure failure) {
    _incrementEventCounter(MetricsCollectorCore.rpcClientTokenGetPolicyFailureCounter);
    final kind = switch (failure) {
      ValidationFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureValidationCounter,
      NetworkFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureNetworkCounter,
      ServerFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureServerCounter,
      NotFoundFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureNotFoundCounter,
      ConnectionFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureConnectionCounter,
      DatabaseFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureDatabaseCounter,
      ConfigurationFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureConfigurationCounter,
      QueryExecutionFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureQueryCounter,
      CompressionFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureCompressionCounter,
      NotificationFailure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureNotificationCounter,
      Failure _ => MetricsCollectorCore.rpcClientTokenGetPolicyFailureOtherCounter,
    };
    _incrementEventCounter(kind);
  }

  void recordClientTokenGetPolicyRateLimited() => _incrementEventCounter(MetricsCollectorCore.rpcClientTokenGetPolicyRateLimitedCounter);
}
