/// Stable `failure.context['reason']` for SQL execution queue, validation, and result-set compression.
abstract final class SqlPipelineContextConstants {
  static const String unexpectedTaskErrorReason = 'unexpected_task_error';

  static const String queueDisposedReason = 'queue_disposed';

  static const String queueWaitTimeoutReason = 'queue_wait_timeout';

  static const String sqlQueueFullReason = 'sql_queue_full';

  static const String sqlValidationFailedReason = 'sql_validation_failed';

  static const String invalidSqlReason = 'invalid_sql';

  static const String resultSetCompressionFailedReason = 'result_set_compression_failed';

  static const String resultSetDecompressionFailedReason = 'result_set_decompression_failed';
}
