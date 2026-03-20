/// Optional observability hooks for auth cache lookups (decision + policy).
abstract class IAuthorizationCacheMetrics {
  void recordDecisionCacheLookup({required bool hit});

  void recordPolicyCacheLookup({required bool hit});
}
