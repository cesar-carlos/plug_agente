/// Collects deprecation usage metrics for observability and removal planning.
abstract class IDeprecationMetricsCollector {
  /// Records usage of the deprecated options.preserve_sql alias.
  void recordPreserveSqlUsage({
    String? requestId,
    String? method,
  });
}
