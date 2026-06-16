/// Stable `failure.context['reason']` / metrics diagnostic strings for ODBC,
/// connection pools, streaming, and related infrastructure paths.
abstract final class OdbcContextConstants {
  static const String authenticationFailedReason = 'authentication_failed';

  static const String bufferTooSmallReason = 'buffer_too_small';

  static const String circuitBreakerOpenReason = 'circuit_breaker_open';

  static const String connectionLostDuringQueryReason = 'connection_lost_during_query';

  static const String configurationLoadFailedReason = 'configuration_load_failed';

  static const String connectionTestRateLimitedReason = 'connection_test_rate_limited';

  static const String connectionTimeoutReason = 'connection_timeout';

  static const String databaseConnectionFailedReason = 'database_connection_failed';

  static const String directConnectionLimitTimeoutReason = 'direct_connection_limit_timeout';

  static const String executionCancelledReason = 'execution_cancelled';

  static const String nativePoolCustomOptionsUnsupportedReason = 'native_pool_custom_options_unsupported';

  static const String odbcDriverNotFoundReason = 'odbc_driver_not_found';

  static const String odbcInitializationFailedReason = 'odbc_initialization_failed';

  static const String odbcMalformedPayloadReason = 'odbc_malformed_payload';

  static const String streamingCellDecodeFailedReason = 'streaming_cell_decode_failed';

  static const String odbcResourceLimitReason = 'odbc_resource_limit';

  static const String odbcWorkerBusyConnectReason = 'odbc_worker_busy_connect';

  static const String odbcWorkerCrashedReason = 'odbc_worker_crashed';

  static const String poolErrorReason = 'pool_error';

  static const String poolExhaustedReason = 'pool_exhausted';

  static const String poolNotCreatedReason = 'pool_not_created';

  static const String poolWaitTimeoutReason = 'pool_wait_timeout';

  static const String serverUnreachableReason = 'server_unreachable';

  static const String socketDisconnectReason = 'socket_disconnect';

  static const String sqlExecutionFailedReason = 'sql_execution_failed';

  static const String sqlPermissionDeniedReason = 'sql_permission_denied';

  static const String streamCancelDisconnectFailedReason = 'stream_cancel_disconnect_failed';

  static const String streamCancelDisconnectTimeoutReason = 'stream_cancel_disconnect_timeout';

  static const String streamDuplicateExecutionIdReason = 'stream_duplicate_execution_id';

  static const String transactionFailedReason = 'transaction_failed';

  static const String transactionRollbackFailedReason = 'transaction_rollback_failed';

  static const String transientQueryFailureReason = 'transient_query_failure';

  static const String odbcWorkerRecoveryInvalidationReason = 'odbc_worker_recovery_invalidation';

  static const String materializedResultUseDbStreamingRecommendation =
      'Enable DB streaming (prefer_db_streaming) or reduce max_rows for large result sets.';

  static const String playgroundMaterializedUseStreamingRecommendation =
      'Enable ODBC streaming mode in Playground or add server-side pagination for large result sets.';

  static String stageBudgetExhaustedReason(String stage) => '${stage}_budget_exhausted';

  static String stageRetryFailedReason(String stage) => '${stage}_retry_failed';
}
