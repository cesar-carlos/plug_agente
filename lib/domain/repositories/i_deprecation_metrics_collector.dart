/// Collects deprecation usage metrics for observability and removal planning.
abstract class IDeprecationMetricsCollector {
  /// Fires after [recordPreserveSqlUsage] increments the counter.
  Stream<void> get updates;

  /// Times [recordPreserveSqlUsage] was called in this session.
  int get preserveSqlUsageCount;

  /// Records usage of the deprecated options.preserve_sql alias.
  void recordPreserveSqlUsage({
    String? requestId,
    String? method,
  });
}
