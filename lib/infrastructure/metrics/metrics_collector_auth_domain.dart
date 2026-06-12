part of 'metrics_collector.dart';

/// Client-token authorization cache and policy metrics.
base mixin MetricsCollectorAuthDomain on MetricsCollectorCore {
  int get authDecisionCacheHitCount => store.counterValue(MetricsCounterNames.authDecisionCacheHitCounter);
  int get authDecisionCacheMissCount => store.counterValue(MetricsCounterNames.authDecisionCacheMissCounter);
  int get authPolicyCacheHitCount => store.counterValue(MetricsCounterNames.authPolicyCacheHitCounter);
  int get authPolicyCacheMissCount => store.counterValue(MetricsCounterNames.authPolicyCacheMissCounter);
  int get rpcClientTokenGetPolicySuccessCount =>
      store.counterValue(MetricsCounterNames.rpcClientTokenGetPolicySuccessCounter);
  int get rpcClientTokenGetPolicyFailureCount =>
      store.counterValue(MetricsCounterNames.rpcClientTokenGetPolicyFailureCounter);
  int get rpcClientTokenGetPolicyRateLimitedCount =>
      store.counterValue(MetricsCounterNames.rpcClientTokenGetPolicyRateLimitedCounter);

  void recordAuthDecisionCacheHit() => _incrementEventCounter(MetricsCounterNames.authDecisionCacheHitCounter);

  void recordAuthDecisionCacheMiss() => _incrementEventCounter(MetricsCounterNames.authDecisionCacheMissCounter);

  void recordAuthPolicyCacheHit() => _incrementEventCounter(MetricsCounterNames.authPolicyCacheHitCounter);

  void recordAuthPolicyCacheMiss() => _incrementEventCounter(MetricsCounterNames.authPolicyCacheMissCounter);

  void recordClientTokenGetPolicySuccess() =>
      _incrementEventCounter(MetricsCounterNames.rpcClientTokenGetPolicySuccessCounter);

  void recordClientTokenGetPolicyFailure(Failure failure) {
    _incrementEventCounter(MetricsCounterNames.rpcClientTokenGetPolicyFailureCounter);
    final kind = switch (failure) {
      ValidationFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureValidationCounter,
      NetworkFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureNetworkCounter,
      ServerFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureServerCounter,
      NotFoundFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureNotFoundCounter,
      ConnectionFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureConnectionCounter,
      DatabaseFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureDatabaseCounter,
      ConfigurationFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureConfigurationCounter,
      QueryExecutionFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureQueryCounter,
      CompressionFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureCompressionCounter,
      NotificationFailure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureNotificationCounter,
      Failure _ => MetricsCounterNames.rpcClientTokenGetPolicyFailureOtherCounter,
    };
    _incrementEventCounter(kind);
  }

  void recordClientTokenGetPolicyRateLimited() =>
      _incrementEventCounter(MetricsCounterNames.rpcClientTokenGetPolicyRateLimitedCounter);
}
