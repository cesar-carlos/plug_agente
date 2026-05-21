/// Stable metrics / diagnostic `reason` strings for SQL batch parallelism and DB streaming paths.
abstract final class RpcSqlDiagnosticsConstants {
  static const String readOnlyParallelGlobalWaitTimeoutReason = 'read_only_parallel_global_wait_timeout';

  static const String readOnlyParallelCappedReason = 'read_only_parallel_capped';

  static const String transactionalNativePoolFallbackReason = 'transactional_native_pool_fallback';

  static const String batchBulkInsertRecommendedReason = 'batch_bulk_insert_recommended';

  static const String autoDbStreamingReason = 'auto_db_streaming';

  static const String preferDbStreamingReason = 'prefer_db_streaming';

  static const String allowlistDbStreamingReason = 'allowlist_db_streaming';
}
