import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_schema_validation_metrics_collector.dart';

/// Servico para coletar e gerenciar metricas de performance.
///
/// Chaves em [_eventCounters] sao estaveis para exportacao (ex.: OpenTelemetry).
class MetricsCollector
    implements
        IMetricsCollector,
        IAutoUpdateMetricsCollector,
        ISchemaValidationMetricsCollector,
        SqlExecutionQueueMetricsCollector,
        ActionExecutionQueueMetricsCollector,
        AgentActionExecutionMetricsCollector {
  MetricsCollector();

  static const String _timeoutCancelSuccessCounter = 'timeout_cancel_success';
  static const String _timeoutCancelFailureCounter = 'timeout_cancel_failure';
  static const String _transactionRollbackFailureCounter = 'transaction_rollback_failure';
  static const String _transactionRollbackAttemptCounter = 'transaction_rollback_attempt';
  static const String _idempotencyFingerprintMismatchCounter = 'idempotency_fingerprint_mismatch';
  static const String _multiResultPoolVacuousFallbackCounter = 'multi_result_pool_vacuous_fallback';
  static const String _multiResultDirectStillVacuousCounter = 'multi_result_direct_still_vacuous';
  static const String _transactionalBatchDirectPathCounter = 'transactional_batch_direct_path';
  static const String _transactionalBatchNativePoolPathCounter = 'transactional_batch_native_pool_path';
  static const String _transactionalBatchNativePoolFallbackCounter = 'transactional_batch_native_pool_fallback';
  static const String _batchBulkInsertRecommendedCounter = 'batch_bulk_insert_recommended';
  static const String _directConnectionFallbackCounter = 'direct_connection_fallback';
  static const String _odbcNativePoolFallbackCounter = 'odbc_native_pool_fallback';
  static const String _odbcNativeFallbackTotalCounter = 'odbc_native_fallback_total';
  static const String _odbcNativePoolOptionsSkipCounter = 'odbc_native_pool_options_skip';
  static const String _odbcNativeCircuitOpenedCounter = 'odbc_native_circuit_opened_total';
  static const String _odbcBufferExpansionCounter = 'odbc_buffer_expansion_total';
  static const String _odbcInvalidConnectionRecycleCounter = 'odbc_invalid_connection_recycle_total';
  static const String _odbcNativeCompatibleAcquireAttemptCounter = 'odbc_native_compatible_acquire_attempt';
  static const String _odbcNativeCompatibleAcquireSuccessCounter = 'odbc_native_compatible_acquire_success';
  static const String _readOnlyBatchParallelCounter = 'read_only_batch_parallel';
  static const String _readOnlyBatchParallelCappedCounter = 'read_only_batch_parallel_capped';
  static const String _directConnectionAcquireTimeoutCounter = 'direct_connection_acquire_timeout';
  static const String _poolReleaseFailureCounter = 'pool_release_failure';
  static const String _poolRecycleCounter = 'pool_recycle';
  static const String _poolRecycleFailureCounter = 'pool_recycle_failure';
  static const String _odbcEventConnectionLostCounter = 'odbc_event_connection_lost';
  static const String _odbcEventAutoReconnectAttemptedCounter = 'odbc_event_auto_reconnect_attempted';
  static const String _odbcEventWorkerRecoveredCounter = 'odbc_event_worker_recovered';
  static const String _odbcEventPoolResizeCounter = 'odbc_event_pool_resize';
  static const String _odbcEventSlowQueryDetectedCounter = 'odbc_event_slow_query_detected';
  static const String _transactionalBatchReadOnlyInferenceCounter = 'transactional_batch_readonly_inference';
  static const String _transactionalBatchDeadlineNearStallCounter = 'transactional_batch_deadline_near_stall';
  static const String _authDecisionCacheHitCounter = 'auth_decision_cache_hit';
  static const String _authDecisionCacheMissCounter = 'auth_decision_cache_miss';
  static const String _authPolicyCacheHitCounter = 'auth_policy_cache_hit';
  static const String _authPolicyCacheMissCounter = 'auth_policy_cache_miss';
  static const String _rpcSqlExecuteStreamingChunksResponseCounter = 'rpc_sql_execute_streaming_chunks_response';
  static const String _rpcSqlExecuteStreamingFromDbResponseCounter = 'rpc_sql_execute_streaming_from_db_response';
  static const String _rpcSqlExecuteAutoStreamingFromDbResponseCounter =
      'rpc_sql_execute_auto_streaming_from_db_response';
  static const String _rpcSqlExecutePreferDbStreamingResponseCounter = 'rpc_sql_execute_prefer_db_streaming_response';
  static const String _rpcSqlExecuteAllowlistDbStreamingResponseCounter =
      'rpc_sql_execute_allowlist_db_streaming_response';
  static const String _rpcSqlExecuteDbStreamingSkipCounter = 'rpc_sql_execute_db_streaming_skip';
  static const String _rpcSqlExecuteMaterializedResponseCounter = 'rpc_sql_execute_materialized_response';
  static const String _rpcStreamTerminalCompleteEmittedCounter = 'rpc_stream_terminal_complete_emitted';
  static const String _rpcStreamTerminalCompleteFailedCounter = 'rpc_stream_terminal_complete_failed';
  static const String _rpcResponseAckRetryCounter = 'rpc_response_ack_retry';
  static const String _rpcResponseAckFallbackWithoutAckCounter = 'rpc_response_ack_fallback_without_ack';
  static const String _rpcClientTokenGetPolicySuccessCounter = 'rpc_client_token_get_policy_success';
  static const String _rpcClientTokenGetPolicyFailureCounter = 'rpc_client_token_get_policy_failure';
  static const String _rpcClientTokenGetPolicyFailureValidationCounter =
      'rpc_client_token_get_policy_failure_validation';
  static const String _rpcClientTokenGetPolicyFailureNetworkCounter = 'rpc_client_token_get_policy_failure_network';
  static const String _rpcClientTokenGetPolicyFailureServerCounter = 'rpc_client_token_get_policy_failure_server';
  static const String _rpcClientTokenGetPolicyFailureNotFoundCounter = 'rpc_client_token_get_policy_failure_not_found';
  static const String _rpcClientTokenGetPolicyFailureConnectionCounter =
      'rpc_client_token_get_policy_failure_connection';
  static const String _rpcClientTokenGetPolicyFailureDatabaseCounter = 'rpc_client_token_get_policy_failure_database';
  static const String _rpcClientTokenGetPolicyFailureConfigurationCounter =
      'rpc_client_token_get_policy_failure_configuration';
  static const String _rpcClientTokenGetPolicyFailureQueryCounter = 'rpc_client_token_get_policy_failure_query';
  static const String _rpcClientTokenGetPolicyFailureCompressionCounter =
      'rpc_client_token_get_policy_failure_compression';
  static const String _rpcClientTokenGetPolicyFailureNotificationCounter =
      'rpc_client_token_get_policy_failure_notification';
  static const String _rpcClientTokenGetPolicyFailureOtherCounter = 'rpc_client_token_get_policy_failure_other';
  static const String _rpcClientTokenGetPolicyRateLimitedCounter = 'rpc_client_token_get_policy_rate_limited';
  static const String _rpcRemoteAgentActionRunSuccessCounter = 'rpc_remote_agent_action_run_success';
  static const String _rpcRemoteAgentActionRunErrorCounter = 'rpc_remote_agent_action_run_error';
  static const String _rpcRemoteAgentActionValidateRunSuccessCounter = 'rpc_remote_agent_action_validate_run_success';
  static const String _rpcRemoteAgentActionValidateRunErrorCounter = 'rpc_remote_agent_action_validate_run_error';
  static const String _rpcRemoteAgentActionCancelSuccessCounter = 'rpc_remote_agent_action_cancel_success';
  static const String _rpcRemoteAgentActionCancelErrorCounter = 'rpc_remote_agent_action_cancel_error';
  static const String _agentActionQueueConcurrencyRejectCounter = 'agent_action_queue_concurrency_reject';
  static const String _agentActionQueueConcurrencyIgnoreCounter = 'agent_action_queue_concurrency_ignore';
  static const String _agentActionQueueDepthFullCounter = 'agent_action_queue_depth_full';
  static const String _agentActionQueuePendingEnqueuedCounter = 'agent_action_queue_pending_enqueued';
  static const String _agentActionQueueIdempotentReplayCounter = 'agent_action_queue_idempotent_replay';
  static const String _agentActionQueueRunStartedCounter = 'agent_action_queue_run_started';
  static const String _agentActionQueuePendingWaitTimeoutCounter = 'agent_action_queue_pending_wait_timeout';
  static const String _agentActionQueuePendingCancelledCounter = 'agent_action_queue_pending_cancelled';
  static const String _agentActionExecutionTerminalSucceededCounter = 'agent_action_execution_terminal_succeeded';
  static const String _agentActionExecutionTerminalFailedCounter = 'agent_action_execution_terminal_failed';
  static const String _agentActionExecutionTerminalSkippedCounter = 'agent_action_execution_terminal_skipped';
  static const String _agentActionExecutionTerminalCancelledCounter = 'agent_action_execution_terminal_cancelled';
  static const String _agentActionExecutionTerminalKilledCounter = 'agent_action_execution_terminal_killed';
  static const String _agentActionExecutionTerminalTimedOutCounter = 'agent_action_execution_terminal_timed_out';
  static const String _agentActionExecutionTerminalInterruptedCounter = 'agent_action_execution_terminal_interrupted';
  static const String _agentActionExecutionTerminalUnknownCounter = 'agent_action_execution_terminal_unknown';
  static const String _agentActionRemotePermissionDeniedCounter = 'agent_action_remote_permission_denied';
  static const String _agentActionLocalAuthorizationDeniedCounter = 'agent_action_local_authorization_denied';
  static const String _agentActionRemoteRateLimitedCounter = 'agent_action_remote_rate_limited';
  static const String _agentActionExecutionHistoryPurgeCounter = 'agent_action_execution_history_purge';
  static const String _agentActionRemoteAuditPurgeCounter = 'agent_action_remote_audit_purge';
  static const String _agentActionRpcIdempotencyCachePurgeCounter = 'agent_action_rpc_idempotency_cache_purge';
  static const String _agentActionElevatedBridgeArtifactsPurgeCounter = 'agent_action_elevated_bridge_artifacts_purge';
  static const String _agentActionRemoteAuditExecutionCorrelatedCounter =
      'agent_action_remote_audit_execution_correlated';
  static const String _agentActionCancelKillFailedCounter = 'agent_action_cancel_kill_failed';
  static const String _agentActionCancelKillPermissionDeniedCounter = 'agent_action_cancel_kill_permission_denied';
  static const String _agentActionCancelProcessNotActiveCounter = 'agent_action_cancel_process_not_active';
  static const String _agentActionCancelProcessIdMismatchCounter = 'agent_action_cancel_process_id_mismatch';
  static const String _agentActionCancelProcessIdentityMismatchCounter =
      'agent_action_cancel_process_identity_mismatch';
  static const String _agentActionCancelProcessIdentityUnavailableCounter =
      'agent_action_cancel_process_identity_unavailable';
  static const String _agentActionCapturedStdoutTruncatedCounter = 'agent_action_captured_output_stdout_truncated';
  static const String _agentActionCapturedStderrTruncatedCounter = 'agent_action_captured_output_stderr_truncated';
  static const String _agentActionCapturedStdoutBytesCounter = 'agent_action_captured_output_stdout_bytes';
  static const String _agentActionCapturedStderrBytesCounter = 'agent_action_captured_output_stderr_bytes';
  static const String _agentActionCapturedOutputClearedCounter = 'agent_action_captured_output_cleared';
  static const String _agentActionElevatedStatusFileTerminalCounter = 'agent_action_elevated_status_file_terminal';
  static const String _agentActionElevatedStatusFileWaitTimeoutCounter =
      'agent_action_elevated_status_file_wait_timeout';
  static const String _rpcRemoteAgentActionGetExecutionSuccessCounter = 'rpc_remote_agent_action_get_execution_success';
  static const String _rpcRemoteAgentActionGetExecutionErrorCounter = 'rpc_remote_agent_action_get_execution_error';
  static const String _rpcRemoteAgentActionRunNotificationRejectedCounter =
      'rpc_remote_agent_action_run_notification_rejected';
  static const String _rpcRemoteAgentActionValidateRunNotificationRejectedCounter =
      'rpc_remote_agent_action_validate_run_notification_rejected';
  static const String _rpcRemoteAgentActionCancelNotificationRejectedCounter =
      'rpc_remote_agent_action_cancel_notification_rejected';
  static const String _rpcRemoteAgentActionGetExecutionNotificationRejectedCounter =
      'rpc_remote_agent_action_get_execution_notification_rejected';
  static const String _rpcRemoteAgentActionBatchReadLimitRejectedCounter =
      'rpc_remote_agent_action_batch_read_limit_rejected';
  static const String _rpcMethodConcurrencyLimitedCounter = 'rpc_method_concurrency_limited';
  static const String _rpcSqlStreamCancelledCounter = 'rpc_sql_stream_cancelled';
  static const String _rpcSqlStreamCancelFailedCounter = 'rpc_sql_stream_cancel_failed';
  static const String _schemaValidationSuccessCounter = 'schema_validation_success_total';
  static const String _schemaValidationFailureCounter = 'schema_validation_failure_total';
  static const String _schemaValidationSkippedLargePayloadCounter = 'schema_validation_skipped_large_payload_total';
  static const String _poolAcquireTimeoutCounter = 'pool_acquire_timeout';
  static const String _connectTimeoutCounter = 'connect_timeout';
  static const String _queryTimeoutCounter = 'query_timeout';
  static const String _preparedStatementReuseCounter = 'prepared_statement_reuse';
  static const String _preparedStatementCacheHitCounter = 'prepared_statement_cache_hit';
  static const String _preparedStatementCacheMissCounter = 'prepared_statement_cache_miss';
  static const String _streamCancelRequestCounter = 'stream_cancel_request';
  static const String _streamCancelBackpressureCounter = 'stream_cancel_backpressure';
  static const String _streamCancelDisconnectFailureCounter = 'stream_cancel_disconnect_failure';
  static const String _streamCancelDisconnectTimeoutCounter = 'stream_cancel_disconnect_timeout';
  static const String _sqlQueueRejectionCounter = 'sql_queue_rejection';
  static const String _sqlQueueTimeoutCounter = 'sql_queue_timeout';
  static const String _sqlQueueSaturation70Counter = 'sql_queue_saturation_70';
  static const String _sqlQueueSaturation90Counter = 'sql_queue_saturation_90';
  static const String _sqlQueueWorkersEqualPoolCounter = 'sql_queue_workers_equal_pool';
  static const String _autoUpdateManualCheckStartedCounter = 'auto_update_manual_check_started';
  static const String _autoUpdateManualCheckSuccessAvailableCounter = 'auto_update_manual_check_success_available';
  static const String _autoUpdateManualCheckSuccessNotAvailableCounter =
      'auto_update_manual_check_success_not_available';
  static const String _autoUpdateManualCheckUpdaterErrorCounter = 'auto_update_manual_check_updater_error';
  static const String _autoUpdateManualCheckTriggerTimeoutCounter = 'auto_update_manual_check_trigger_timeout';
  static const String _autoUpdateManualCheckCompletionTimeoutCounter = 'auto_update_manual_check_completion_timeout';
  static const String _autoUpdateManualCheckTriggerFailureCounter = 'auto_update_manual_check_trigger_failure';
  static const String _autoUpdateManualCheckNotInitializedCounter = 'auto_update_manual_check_not_initialized';
  static const String _autoUpdateCircuitOpenedCounter = 'auto_update_circuit_opened';
  static const String _autoUpdateCircuitOpenRejectedCounter = 'auto_update_circuit_open_rejected';
  static const String _autoUpdateBackgroundCheckTriggerFailureCounter = 'auto_update_background_check_trigger_failure';
  static const String _autoUpdateBackgroundCheckUpdaterErrorCounter = 'auto_update_background_check_updater_error';

  static const int _maxMetrics = 10000;

  final List<QueryMetrics> _metrics = [];
  final _metricsController = StreamController<QueryMetrics>.broadcast();
  final Map<String, int> _eventCounters = <String, int>{};
  int _activeDirectConnections = 0;
  int _maxActiveDirectConnections = 0;
  int _currentQueueSize = 0;
  int _maxQueueSize = 0;
  int _currentActiveWorkers = 0;
  int _maxActiveWorkers = 0;
  // ListQueue gives O(1) addLast + removeFirst vs O(n) List.removeAt(0)
  // when the ring-buffer cap (_maxWaitTimeSamples) is reached.
  final ListQueue<Duration> _queueWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> _agentActionQueueWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> _agentActionExecutionDurations = ListQueue<Duration>();
  final ListQueue<Duration> _poolWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> _directConnectionWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> _readOnlyBatchParallelWaitTimes = ListQueue<Duration>();
  final ListQueue<Duration> _connectTimes = ListQueue<Duration>();
  final ListQueue<Duration> _sqlExecutionTimes = ListQueue<Duration>();
  final Map<String, ListQueue<Duration>> _sqlExecutionTimesByMode = <String, ListQueue<Duration>>{};
  final Map<String, ListQueue<DateTime>> _sqlExecutionTimestampsByMode = <String, ListQueue<DateTime>>{};
  final ListQueue<Duration> _preparedPrepareTimes = ListQueue<Duration>();
  final Map<String, int> _streamingSkipReasons = <String, int>{};
  final Map<String, int> _odbcNativeFallbackReasons = <String, int>{};
  final Map<String, int> _odbcQueryTimeoutByStage = <String, int>{};
  final Map<String, int> _schemaValidationDurationUsByKey = <String, int>{};
  final Map<String, int> _schemaValidationCountByKey = <String, int>{};
  final Map<String, int> _schemaValidationFailuresByKey = <String, int>{};
  int _schemaValidationDurationUs = 0;
  int _readOnlyBatchParallelLastRequested = 0;
  int _readOnlyBatchParallelLastEffective = 0;
  final Queue<String> _recentDiagnosticReasons = Queue<String>();
  static const int _maxWaitTimeSamples = 1000;
  static const int _maxRecentDiagnosticReasons = 50;

  @override
  Stream<QueryMetrics> get metricsStream => _metricsController.stream;

  @override
  List<QueryMetrics> get metrics => List.unmodifiable(_metrics);

  /// Numero de metricas coletadas.
  int get count => _metrics.length;
  int get timeoutCancelSuccessCount => _eventCounters[_timeoutCancelSuccessCounter] ?? 0;
  int get timeoutCancelFailureCount => _eventCounters[_timeoutCancelFailureCounter] ?? 0;
  int get transactionRollbackFailureCount => _eventCounters[_transactionRollbackFailureCounter] ?? 0;
  int get transactionRollbackAttemptCount => _eventCounters[_transactionRollbackAttemptCounter] ?? 0;
  int get idempotencyFingerprintMismatchCount => _eventCounters[_idempotencyFingerprintMismatchCounter] ?? 0;
  int get multiResultPoolVacuousFallbackCount => _eventCounters[_multiResultPoolVacuousFallbackCounter] ?? 0;
  int get multiResultDirectStillVacuousCount => _eventCounters[_multiResultDirectStillVacuousCounter] ?? 0;
  int get transactionalBatchDirectPathCount => _eventCounters[_transactionalBatchDirectPathCounter] ?? 0;
  int get transactionalBatchNativePoolPathCount => _eventCounters[_transactionalBatchNativePoolPathCounter] ?? 0;
  int get transactionalBatchNativePoolFallbackCount =>
      _eventCounters[_transactionalBatchNativePoolFallbackCounter] ?? 0;
  int get batchBulkInsertRecommendedCount => _eventCounters[_batchBulkInsertRecommendedCounter] ?? 0;
  int get directConnectionFallbackCount => _eventCounters[_directConnectionFallbackCounter] ?? 0;
  int get odbcNativePoolFallbackCount => _eventCounters[_odbcNativePoolFallbackCounter] ?? 0;
  int get odbcNativePoolOptionsSkipCount => _eventCounters[_odbcNativePoolOptionsSkipCounter] ?? 0;
  int get odbcNativeCompatibleAcquireAttemptCount => _eventCounters[_odbcNativeCompatibleAcquireAttemptCounter] ?? 0;
  int get odbcNativeCompatibleAcquireSuccessCount => _eventCounters[_odbcNativeCompatibleAcquireSuccessCounter] ?? 0;
  int get readOnlyBatchParallelCount => _eventCounters[_readOnlyBatchParallelCounter] ?? 0;
  int get readOnlyBatchParallelCappedCount => _eventCounters[_readOnlyBatchParallelCappedCounter] ?? 0;
  int get directConnectionAcquireTimeoutCount => _eventCounters[_directConnectionAcquireTimeoutCounter] ?? 0;
  int get activeDirectConnections => _activeDirectConnections;
  int get maxActiveDirectConnections => _maxActiveDirectConnections;
  int get poolReleaseFailureCount => _eventCounters[_poolReleaseFailureCounter] ?? 0;
  int get poolRecycleCount => _eventCounters[_poolRecycleCounter] ?? 0;
  int get poolRecycleFailureCount => _eventCounters[_poolRecycleFailureCounter] ?? 0;
  int get authDecisionCacheHitCount => _eventCounters[_authDecisionCacheHitCounter] ?? 0;
  int get authDecisionCacheMissCount => _eventCounters[_authDecisionCacheMissCounter] ?? 0;
  int get authPolicyCacheHitCount => _eventCounters[_authPolicyCacheHitCounter] ?? 0;
  int get authPolicyCacheMissCount => _eventCounters[_authPolicyCacheMissCounter] ?? 0;
  int get rpcSqlExecuteStreamingChunksResponseCount =>
      _eventCounters[_rpcSqlExecuteStreamingChunksResponseCounter] ?? 0;
  int get rpcSqlExecuteStreamingFromDbResponseCount =>
      _eventCounters[_rpcSqlExecuteStreamingFromDbResponseCounter] ?? 0;
  int get rpcSqlExecuteAutoStreamingFromDbResponseCount =>
      _eventCounters[_rpcSqlExecuteAutoStreamingFromDbResponseCounter] ?? 0;
  int get rpcSqlExecuteAllowlistDbStreamingResponseCount =>
      _eventCounters[_rpcSqlExecuteAllowlistDbStreamingResponseCounter] ?? 0;
  int get rpcSqlExecuteMaterializedResponseCount => _eventCounters[_rpcSqlExecuteMaterializedResponseCounter] ?? 0;
  int get rpcStreamTerminalCompleteEmittedCount => _eventCounters[_rpcStreamTerminalCompleteEmittedCounter] ?? 0;
  int get rpcStreamTerminalCompleteFailedCount => _eventCounters[_rpcStreamTerminalCompleteFailedCounter] ?? 0;
  int get rpcResponseAckRetryCount => _eventCounters[_rpcResponseAckRetryCounter] ?? 0;
  int get rpcResponseAckFallbackWithoutAckCount => _eventCounters[_rpcResponseAckFallbackWithoutAckCounter] ?? 0;
  int get rpcClientTokenGetPolicySuccessCount => _eventCounters[_rpcClientTokenGetPolicySuccessCounter] ?? 0;
  int get rpcClientTokenGetPolicyFailureCount => _eventCounters[_rpcClientTokenGetPolicyFailureCounter] ?? 0;
  int get rpcClientTokenGetPolicyRateLimitedCount => _eventCounters[_rpcClientTokenGetPolicyRateLimitedCounter] ?? 0;
  int get poolAcquireTimeoutCount => _eventCounters[_poolAcquireTimeoutCounter] ?? 0;
  int get connectTimeoutCount => _eventCounters[_connectTimeoutCounter] ?? 0;
  int get queryTimeoutCount => _eventCounters[_queryTimeoutCounter] ?? 0;
  int get preparedStatementReuseCount => _eventCounters[_preparedStatementReuseCounter] ?? 0;
  int get preparedStatementCacheHitCount => _eventCounters[_preparedStatementCacheHitCounter] ?? 0;
  int get preparedStatementCacheMissCount => _eventCounters[_preparedStatementCacheMissCounter] ?? 0;
  int get streamCancelRequestCount => _eventCounters[_streamCancelRequestCounter] ?? 0;
  int get streamCancelBackpressureCount => _eventCounters[_streamCancelBackpressureCounter] ?? 0;
  int get streamCancelDisconnectFailureCount => _eventCounters[_streamCancelDisconnectFailureCounter] ?? 0;
  int get streamCancelDisconnectTimeoutCount => _eventCounters[_streamCancelDisconnectTimeoutCounter] ?? 0;
  int get sqlQueueRejectionCount => _eventCounters[_sqlQueueRejectionCounter] ?? 0;
  int get sqlQueueTimeoutCount => _eventCounters[_sqlQueueTimeoutCounter] ?? 0;
  int get sqlQueueSaturation70Count => _eventCounters[_sqlQueueSaturation70Counter] ?? 0;
  int get sqlQueueSaturation90Count => _eventCounters[_sqlQueueSaturation90Counter] ?? 0;
  int get sqlQueueWorkersEqualPoolCount => _eventCounters[_sqlQueueWorkersEqualPoolCounter] ?? 0;
  int get autoUpdateManualCheckStartedCount => _eventCounters[_autoUpdateManualCheckStartedCounter] ?? 0;
  int get autoUpdateManualCheckSuccessAvailableCount =>
      _eventCounters[_autoUpdateManualCheckSuccessAvailableCounter] ?? 0;
  int get autoUpdateManualCheckSuccessNotAvailableCount =>
      _eventCounters[_autoUpdateManualCheckSuccessNotAvailableCounter] ?? 0;
  int get autoUpdateManualCheckUpdaterErrorCount => _eventCounters[_autoUpdateManualCheckUpdaterErrorCounter] ?? 0;
  int get autoUpdateManualCheckTriggerTimeoutCount => _eventCounters[_autoUpdateManualCheckTriggerTimeoutCounter] ?? 0;
  int get autoUpdateManualCheckCompletionTimeoutCount =>
      _eventCounters[_autoUpdateManualCheckCompletionTimeoutCounter] ?? 0;
  int get autoUpdateManualCheckTriggerFailureCount => _eventCounters[_autoUpdateManualCheckTriggerFailureCounter] ?? 0;
  int get autoUpdateManualCheckNotInitializedCount => _eventCounters[_autoUpdateManualCheckNotInitializedCounter] ?? 0;
  int get autoUpdateCircuitOpenedCount => _eventCounters[_autoUpdateCircuitOpenedCounter] ?? 0;
  int get autoUpdateCircuitOpenRejectedCount => _eventCounters[_autoUpdateCircuitOpenRejectedCounter] ?? 0;
  int get autoUpdateBackgroundCheckTriggerFailureCount =>
      _eventCounters[_autoUpdateBackgroundCheckTriggerFailureCounter] ?? 0;
  int get autoUpdateBackgroundCheckUpdaterErrorCount =>
      _eventCounters[_autoUpdateBackgroundCheckUpdaterErrorCounter] ?? 0;
  int get currentQueueSize => _currentQueueSize;
  int get maxQueueSize => _maxQueueSize;
  int get currentActiveWorkers => _currentActiveWorkers;
  int get maxActiveWorkers => _maxActiveWorkers;

  /// Average queue wait time across recent samples.
  Duration? get averageQueueWaitTime {
    if (_queueWaitTimes.isEmpty) return null;
    final totalMs = _queueWaitTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ _queueWaitTimes.length);
  }

  Duration? get p95QueueWaitTime {
    if (_queueWaitTimes.isEmpty) return null;
    final waitTimes = _sortedQueueWaitTimesMs();
    return Duration(milliseconds: waitTimes[(waitTimes.length * 0.95).floor()]);
  }

  Duration? get maxRecentQueueWaitTime {
    if (_queueWaitTimes.isEmpty) return null;
    final waitTimes = _sortedQueueWaitTimesMs();
    return Duration(milliseconds: waitTimes.last);
  }

  Map<String, int> get eventCounters => UnmodifiableMapView<String, int>(_eventCounters);

  /// Limpa todas as metricas.
  void clear() {
    _metrics.clear();
    _eventCounters.clear();
    _activeDirectConnections = 0;
    _maxActiveDirectConnections = 0;
    _currentQueueSize = 0;
    _maxQueueSize = 0;
    _currentActiveWorkers = 0;
    _maxActiveWorkers = 0;
    _queueWaitTimes.clear();
    _autoUpdateProbeTimes.clear();
    _autoUpdateDownloadTimes.clear();
    _agentActionQueueWaitTimes.clear();
    _agentActionExecutionDurations.clear();
    _poolWaitTimes.clear();
    _directConnectionWaitTimes.clear();
    _readOnlyBatchParallelWaitTimes.clear();
    _connectTimes.clear();
    _sqlExecutionTimes.clear();
    _sqlExecutionTimesByMode.clear();
    _sqlExecutionTimestampsByMode.clear();
    _preparedPrepareTimes.clear();
    _streamingSkipReasons.clear();
    _odbcNativeFallbackReasons.clear();
    _odbcQueryTimeoutByStage.clear();
    _schemaValidationDurationUsByKey.clear();
    _schemaValidationCountByKey.clear();
    _schemaValidationFailuresByKey.clear();
    _schemaValidationDurationUs = 0;
    _readOnlyBatchParallelLastRequested = 0;
    _readOnlyBatchParallelLastEffective = 0;
    _recentDiagnosticReasons.clear();
  }

  // SQL Execution Queue metrics implementation

  @override
  void recordQueueAdded(int currentSize) {
    recordQueueSizeChanged(currentSize);
  }

  @override
  void recordQueueSizeChanged(int currentSize) {
    _currentQueueSize = currentSize;
    if (currentSize > _maxQueueSize) {
      _maxQueueSize = currentSize;
    }
  }

  @override
  void recordQueueRejection() {
    _incrementEventCounter(_sqlQueueRejectionCounter);
  }

  @override
  void recordQueueTimeout() {
    _incrementEventCounter(_sqlQueueTimeoutCounter);
  }

  @override
  void recordQueueSaturation({required int thresholdPercent, required int currentSize, required int maxSize}) {
    final counter = switch (thresholdPercent) {
      70 => _sqlQueueSaturation70Counter,
      90 => _sqlQueueSaturation90Counter,
      _ => 'sql_queue_saturation_$thresholdPercent',
    };
    _incrementEventCounter(counter);
    developer.log(
      'SQL queue saturation crossed $thresholdPercent%',
      name: 'metrics',
      level: 900,
      error: {
        'current_size': currentSize,
        'max_size': maxSize,
        'threshold_percent': thresholdPercent,
      },
    );
  }

  @override
  void recordQueueWaitTime(Duration waitTime) {
    _recordDurationSample(_queueWaitTimes, waitTime);
  }

  @override
  void recordConcurrencyReject() {
    _incrementEventCounter(_agentActionQueueConcurrencyRejectCounter);
  }

  @override
  void recordConcurrencyIgnore() {
    _incrementEventCounter(_agentActionQueueConcurrencyIgnoreCounter);
  }

  @override
  void recordQueueDepthFull() {
    _incrementEventCounter(_agentActionQueueDepthFullCounter);
  }

  @override
  void recordPendingEnqueued() {
    _incrementEventCounter(_agentActionQueuePendingEnqueuedCounter);
  }

  @override
  void recordIdempotentReplay() {
    _incrementEventCounter(_agentActionQueueIdempotentReplayCounter);
  }

  @override
  void recordRunStarted() {
    _incrementEventCounter(_agentActionQueueRunStartedCounter);
  }

  @override
  void recordPendingWaitTimeout() {
    _incrementEventCounter(_agentActionQueuePendingWaitTimeoutCounter);
  }

  @override
  void recordPendingCancelled() {
    _incrementEventCounter(_agentActionQueuePendingCancelledCounter);
  }

  @override
  void recordPendingDequeueWaitTime(Duration wait) {
    _recordDurationSample(_agentActionQueueWaitTimes, wait);
  }

  @override
  void recordTerminalOutcome(AgentActionExecutionStatus status) {
    final counter = switch (status) {
      AgentActionExecutionStatus.succeeded => _agentActionExecutionTerminalSucceededCounter,
      AgentActionExecutionStatus.failed => _agentActionExecutionTerminalFailedCounter,
      AgentActionExecutionStatus.skipped => _agentActionExecutionTerminalSkippedCounter,
      AgentActionExecutionStatus.cancelled => _agentActionExecutionTerminalCancelledCounter,
      AgentActionExecutionStatus.killed => _agentActionExecutionTerminalKilledCounter,
      AgentActionExecutionStatus.timedOut => _agentActionExecutionTerminalTimedOutCounter,
      AgentActionExecutionStatus.interrupted => _agentActionExecutionTerminalInterruptedCounter,
      AgentActionExecutionStatus.unknown => _agentActionExecutionTerminalUnknownCounter,
      AgentActionExecutionStatus.queued || AgentActionExecutionStatus.running => null,
    };
    if (counter != null) {
      _incrementEventCounter(counter);
    }
  }

  @override
  void recordExecutionDuration(Duration duration) {
    if (duration.isNegative) {
      return;
    }
    _recordDurationSample(_agentActionExecutionDurations, duration);
  }

  @override
  void recordRemotePermissionDenied() {
    _incrementEventCounter(_agentActionRemotePermissionDeniedCounter);
  }

  @override
  void recordLocalAuthorizationDenied() {
    _incrementEventCounter(_agentActionLocalAuthorizationDeniedCounter);
  }

  void recordRemoteRateLimited() {
    _incrementEventCounter(_agentActionRemoteRateLimitedCounter);
  }

  @override
  void recordExecutionHistoryPurge(int removedCount) {
    _incrementEventCounterBy(_agentActionExecutionHistoryPurgeCounter, removedCount);
  }

  @override
  void recordRemoteAuditPurge(int removedCount) {
    _incrementEventCounterBy(_agentActionRemoteAuditPurgeCounter, removedCount);
  }

  @override
  void recordRpcIdempotencyCachePurge(int removedCount) {
    _incrementEventCounterBy(_agentActionRpcIdempotencyCachePurgeCounter, removedCount);
  }

  @override
  void recordElevatedBridgeArtifactsPurge(int removedCount) {
    _incrementEventCounterBy(_agentActionElevatedBridgeArtifactsPurgeCounter, removedCount);
  }

  @override
  void recordRemoteAuditExecutionCorrelated() {
    _incrementEventCounter(_agentActionRemoteAuditExecutionCorrelatedCounter);
  }

  @override
  void recordCancelKillFailed() {
    _incrementEventCounter(_agentActionCancelKillFailedCounter);
  }

  @override
  void recordCancelKillPermissionDenied() {
    _incrementEventCounter(_agentActionCancelKillPermissionDeniedCounter);
  }

  @override
  void recordCancelProcessNotActive() {
    _incrementEventCounter(_agentActionCancelProcessNotActiveCounter);
  }

  @override
  void recordCancelProcessIdMismatch() {
    _incrementEventCounter(_agentActionCancelProcessIdMismatchCounter);
  }

  @override
  void recordCancelProcessIdentityMismatch() {
    _incrementEventCounter(_agentActionCancelProcessIdentityMismatchCounter);
  }

  @override
  void recordCancelProcessIdentityUnavailable() {
    _incrementEventCounter(_agentActionCancelProcessIdentityUnavailableCounter);
  }

  @override
  void recordCapturedOutputPersisted({
    required bool stdoutCaptured,
    required bool stderrCaptured,
    required bool stdoutTruncated,
    required bool stderrTruncated,
    int stdoutUtf8Bytes = 0,
    int stderrUtf8Bytes = 0,
  }) {
    if (stdoutCaptured && stdoutTruncated) {
      _incrementEventCounter(_agentActionCapturedStdoutTruncatedCounter);
    }
    if (stderrCaptured && stderrTruncated) {
      _incrementEventCounter(_agentActionCapturedStderrTruncatedCounter);
    }
    _incrementEventCounterBy(_agentActionCapturedStdoutBytesCounter, stdoutUtf8Bytes);
    _incrementEventCounterBy(_agentActionCapturedStderrBytesCounter, stderrUtf8Bytes);
  }

  @override
  void recordCapturedOutputCleared(int executionCount) {
    _incrementEventCounterBy(_agentActionCapturedOutputClearedCounter, executionCount);
  }

  @override
  void recordElevatedStatusFileTerminalRead() {
    _incrementEventCounter(_agentActionElevatedStatusFileTerminalCounter);
  }

  @override
  void recordElevatedStatusFileWaitTimeout() {
    _incrementEventCounter(_agentActionElevatedStatusFileWaitTimeoutCounter);
  }

  void recordPoolWaitTime(Duration waitTime) => _recordDurationSample(_poolWaitTimes, waitTime);

  void recordDirectConnectionWaitTime(Duration waitTime) => _recordDurationSample(_directConnectionWaitTimes, waitTime);

  void recordReadOnlyBatchParallelWaitTime(Duration waitTime) =>
      _recordDurationSample(_readOnlyBatchParallelWaitTimes, waitTime);

  void recordConnectTime(Duration connectTime) => _recordDurationSample(_connectTimes, connectTime);

  void recordSqlExecutionTime(
    Duration executionTime, {
    String mode = 'unknown',
  }) {
    _recordDurationSample(_sqlExecutionTimes, executionTime);
    final samples = _sqlExecutionTimesByMode.putIfAbsent(mode, ListQueue<Duration>.new);
    _recordDurationSample(samples, executionTime);
    final timestamps = _sqlExecutionTimestampsByMode.putIfAbsent(mode, ListQueue<DateTime>.new);
    _recordTimestampSample(timestamps, DateTime.now());
  }

  void recordPreparedPrepareTime(Duration prepareTime) => _recordDurationSample(_preparedPrepareTimes, prepareTime);

  @override
  void recordWorkerStarted(int activeCount) {
    _currentActiveWorkers = activeCount;
    if (activeCount > _maxActiveWorkers) {
      _maxActiveWorkers = activeCount;
    }
  }

  @override
  void recordWorkerCompleted(int activeCount) {
    _currentActiveWorkers = activeCount;
  }

  void recordTimeoutCancelSuccess() => _incrementEventCounter(_timeoutCancelSuccessCounter);

  void recordTimeoutCancelFailure() => _incrementEventCounter(_timeoutCancelFailureCounter);

  void recordTransactionRollbackAttempt() => _incrementEventCounter(_transactionRollbackAttemptCounter);

  void recordTransactionRollbackFailure() => _incrementEventCounter(_transactionRollbackFailureCounter);

  void recordIdempotencyFingerprintMismatch() => _incrementEventCounter(_idempotencyFingerprintMismatchCounter);

  void recordMultiResultPoolVacuousFallback() => _incrementEventCounter(_multiResultPoolVacuousFallbackCounter);

  void recordMultiResultDirectStillVacuous() => _incrementEventCounter(_multiResultDirectStillVacuousCounter);

  void recordTransactionalBatchDirectPath() => _incrementEventCounter(_transactionalBatchDirectPathCounter);

  void recordTransactionalBatchNativePoolPath() => _incrementEventCounter(_transactionalBatchNativePoolPathCounter);

  void recordTransactionalBatchNativePoolFallback() =>
      _incrementEventCounter(_transactionalBatchNativePoolFallbackCounter);

  void recordBatchBulkInsertRecommended() {
    _incrementEventCounter(_batchBulkInsertRecommendedCounter);
    recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.batchBulkInsertRecommendedReason,
    );
  }

  void recordDirectConnectionFallback() => _incrementEventCounter(_directConnectionFallbackCounter);

  void recordOdbcNativePoolFallback() => _incrementEventCounter(_odbcNativePoolFallbackCounter);

  void recordOdbcNativeFallback(String reason) {
    final normalizedReason = reason.trim().isEmpty ? 'unknown' : reason.trim();
    _incrementEventCounter(_odbcNativeFallbackTotalCounter);
    _odbcNativeFallbackReasons[normalizedReason] = (_odbcNativeFallbackReasons[normalizedReason] ?? 0) + 1;
    recordDiagnosticReason(
      category: 'odbc_native_fallback',
      reason: normalizedReason,
    );
  }

  void recordOdbcNativeCircuitOpened() {
    _incrementEventCounter(_odbcNativeCircuitOpenedCounter);
    recordDiagnosticReason(
      category: 'odbc_native',
      reason: 'native_circuit_open',
    );
  }

  void recordOdbcBufferExpansion() => _incrementEventCounter(_odbcBufferExpansionCounter);

  void recordOdbcInvalidConnectionRecycle() => _incrementEventCounter(_odbcInvalidConnectionRecycleCounter);

  void recordOdbcNativePoolOptionsSkip() => _incrementEventCounter(_odbcNativePoolOptionsSkipCounter);

  void recordOdbcNativeCompatibleAcquireAttempt() => _incrementEventCounter(_odbcNativeCompatibleAcquireAttemptCounter);

  void recordOdbcNativeCompatibleAcquireSuccess() => _incrementEventCounter(_odbcNativeCompatibleAcquireSuccessCounter);

  void recordReadOnlyBatchParallel({
    int? requestedParallelism,
    int? effectiveParallelism,
  }) {
    _incrementEventCounter(_readOnlyBatchParallelCounter);
    if (requestedParallelism != null) {
      _readOnlyBatchParallelLastRequested = requestedParallelism;
    }
    if (effectiveParallelism != null) {
      _readOnlyBatchParallelLastEffective = effectiveParallelism;
    }
    if (requestedParallelism != null && effectiveParallelism != null && effectiveParallelism < requestedParallelism) {
      _incrementEventCounter(_readOnlyBatchParallelCappedCounter);
      recordDiagnosticReason(
        category: 'batch',
        reason: RpcSqlDiagnosticsConstants.readOnlyParallelCappedReason,
      );
    }
  }

  void recordDirectConnectionAcquireTimeout() => _incrementEventCounter(_directConnectionAcquireTimeoutCounter);

  void recordDirectConnectionOpened() {
    _activeDirectConnections++;
    if (_activeDirectConnections > _maxActiveDirectConnections) {
      _maxActiveDirectConnections = _activeDirectConnections;
    }
    _incrementEventCounter('direct_connection_opened');
  }

  void recordDirectConnectionClosed() {
    if (_activeDirectConnections > 0) {
      _activeDirectConnections--;
    }
    _incrementEventCounter('direct_connection_closed');
  }

  void recordPoolReleaseFailure() => _incrementEventCounter(_poolReleaseFailureCounter);

  void recordPoolRecycle() => _incrementEventCounter(_poolRecycleCounter);

  void recordPoolRecycleFailure() => _incrementEventCounter(_poolRecycleFailureCounter);

  /// Counts ODBC runtime events forwarded by `OdbcEventBridge` so dashboards
  /// have a quantitative view of connection/pool/slow-query lifecycle without
  /// scraping logs.
  void recordOdbcEventConnectionLost() => _incrementEventCounter(_odbcEventConnectionLostCounter);

  void recordOdbcEventAutoReconnectAttempted() => _incrementEventCounter(_odbcEventAutoReconnectAttemptedCounter);

  void recordOdbcEventWorkerRecovered() => _incrementEventCounter(_odbcEventWorkerRecoveredCounter);

  void recordOdbcEventPoolResize() => _incrementEventCounter(_odbcEventPoolResizeCounter);

  void recordOdbcEventSlowQueryDetected() => _incrementEventCounter(_odbcEventSlowQueryDetectedCounter);

  /// Counts transactional batches that started with the engine-side read-only
  /// hint (`TransactionAccessMode.readOnly`). Confirms the inference is firing
  /// in production and lets dashboards correlate read-only batches with
  /// fewer engine-side locks.
  void recordTransactionalBatchReadOnlyInference() => _incrementEventCounter(_transactionalBatchReadOnlyInferenceCounter);

  /// Counts transactional batches that consumed more than 80% of the active
  /// deadline before completing. High values suggest the batch is at risk of
  /// timing out and leaving locks while the rollback cleanup runs.
  void recordTransactionalBatchDeadlineNearStall() =>
      _incrementEventCounter(_transactionalBatchDeadlineNearStallCounter);

  void recordAuthDecisionCacheHit() => _incrementEventCounter(_authDecisionCacheHitCounter);

  void recordAuthDecisionCacheMiss() => _incrementEventCounter(_authDecisionCacheMissCounter);

  void recordAuthPolicyCacheHit() => _incrementEventCounter(_authPolicyCacheHitCounter);

  void recordAuthPolicyCacheMiss() => _incrementEventCounter(_authPolicyCacheMissCounter);

  void recordRpcSqlExecuteStreamingChunksResponse() =>
      _incrementEventCounter(_rpcSqlExecuteStreamingChunksResponseCounter);

  void recordRpcSqlExecuteStreamingFromDbResponse() =>
      _incrementEventCounter(_rpcSqlExecuteStreamingFromDbResponseCounter);

  void recordRpcSqlExecuteAutoStreamingFromDbResponse() {
    _incrementEventCounter(_rpcSqlExecuteAutoStreamingFromDbResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.autoDbStreamingReason,
    );
  }

  void recordRpcSqlExecutePreferDbStreamingResponse() {
    _incrementEventCounter(_rpcSqlExecutePreferDbStreamingResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.preferDbStreamingReason,
    );
  }

  void recordRpcSqlExecuteAllowlistDbStreamingResponse() {
    _incrementEventCounter(_rpcSqlExecuteAllowlistDbStreamingResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.allowlistDbStreamingReason,
    );
  }

  void recordRpcSqlExecuteDbStreamingSkipped(String reason) {
    _incrementEventCounter(_rpcSqlExecuteDbStreamingSkipCounter);
    _streamingSkipReasons[reason] = (_streamingSkipReasons[reason] ?? 0) + 1;
    recordDiagnosticReason(
      category: 'streaming_skip',
      reason: reason,
    );
  }

  void recordRpcSqlExecuteMaterializedResponse() => _incrementEventCounter(_rpcSqlExecuteMaterializedResponseCounter);

  void recordRpcStreamTerminalCompleteEmitted() => _incrementEventCounter(_rpcStreamTerminalCompleteEmittedCounter);

  void recordRpcStreamTerminalCompleteFailed() => _incrementEventCounter(_rpcStreamTerminalCompleteFailedCounter);

  void recordRpcResponseAckRetry() => _incrementEventCounter(_rpcResponseAckRetryCounter);

  void recordRpcResponseAckFallbackWithoutAck() => _incrementEventCounter(_rpcResponseAckFallbackWithoutAckCounter);

  void recordClientTokenGetPolicySuccess() => _incrementEventCounter(_rpcClientTokenGetPolicySuccessCounter);

  void recordClientTokenGetPolicyFailure(Failure failure) {
    _incrementEventCounter(_rpcClientTokenGetPolicyFailureCounter);
    final kind = switch (failure) {
      ValidationFailure _ => _rpcClientTokenGetPolicyFailureValidationCounter,
      NetworkFailure _ => _rpcClientTokenGetPolicyFailureNetworkCounter,
      ServerFailure _ => _rpcClientTokenGetPolicyFailureServerCounter,
      NotFoundFailure _ => _rpcClientTokenGetPolicyFailureNotFoundCounter,
      ConnectionFailure _ => _rpcClientTokenGetPolicyFailureConnectionCounter,
      DatabaseFailure _ => _rpcClientTokenGetPolicyFailureDatabaseCounter,
      ConfigurationFailure _ => _rpcClientTokenGetPolicyFailureConfigurationCounter,
      QueryExecutionFailure _ => _rpcClientTokenGetPolicyFailureQueryCounter,
      CompressionFailure _ => _rpcClientTokenGetPolicyFailureCompressionCounter,
      NotificationFailure _ => _rpcClientTokenGetPolicyFailureNotificationCounter,
      Failure _ => _rpcClientTokenGetPolicyFailureOtherCounter,
    };
    _incrementEventCounter(kind);
  }

  void recordClientTokenGetPolicyRateLimited() => _incrementEventCounter(_rpcClientTokenGetPolicyRateLimitedCounter);

  void recordRpcAgentActionRemoteOutcome(String rpcMethod, {required bool success}) {
    if (!AgentActionRpcConstants.remotePublishedRpcMethodNames.contains(rpcMethod)) {
      return;
    }
    final counter = switch ((rpcMethod, success)) {
      (AgentActionRpcConstants.agentActionRunRpcMethodName, true) => _rpcRemoteAgentActionRunSuccessCounter,
      (AgentActionRpcConstants.agentActionRunRpcMethodName, false) => _rpcRemoteAgentActionRunErrorCounter,
      (AgentActionRpcConstants.agentActionValidateRunRpcMethodName, true) =>
        _rpcRemoteAgentActionValidateRunSuccessCounter,
      (AgentActionRpcConstants.agentActionValidateRunRpcMethodName, false) =>
        _rpcRemoteAgentActionValidateRunErrorCounter,
      (AgentActionRpcConstants.agentActionCancelRpcMethodName, true) => _rpcRemoteAgentActionCancelSuccessCounter,
      (AgentActionRpcConstants.agentActionCancelRpcMethodName, false) => _rpcRemoteAgentActionCancelErrorCounter,
      (AgentActionRpcConstants.agentActionGetExecutionRpcMethodName, true) =>
        _rpcRemoteAgentActionGetExecutionSuccessCounter,
      (AgentActionRpcConstants.agentActionGetExecutionRpcMethodName, false) =>
        _rpcRemoteAgentActionGetExecutionErrorCounter,
      _ => null,
    };
    if (counter != null) {
      _incrementEventCounter(counter);
    }
  }

  void recordRpcAgentActionNotificationRejected(String rpcMethod) {
    if (!AgentActionRpcConstants.remotePublishedRpcMethodNames.contains(rpcMethod)) {
      return;
    }
    final counter = switch (rpcMethod) {
      AgentActionRpcConstants.agentActionRunRpcMethodName => _rpcRemoteAgentActionRunNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionValidateRunRpcMethodName =>
        _rpcRemoteAgentActionValidateRunNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionCancelRpcMethodName => _rpcRemoteAgentActionCancelNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionGetExecutionRpcMethodName =>
        _rpcRemoteAgentActionGetExecutionNotificationRejectedCounter,
      _ => null,
    };
    if (counter != null) {
      _incrementEventCounter(counter);
    }
  }

  void recordRpcAgentActionBatchReadLimitRejected() {
    _incrementEventCounter(_rpcRemoteAgentActionBatchReadLimitRejectedCounter);
  }

  void recordRpcMethodConcurrencyLimited(String rpcMethod) {
    _incrementEventCounter(_rpcMethodConcurrencyLimitedCounter);
    recordDiagnosticReason(
      category: 'rpc_method_concurrency_limit',
      reason: rpcMethod,
    );
  }

  void recordSqlStreamCancelled(String reason) {
    _incrementEventCounter(_rpcSqlStreamCancelledCounter);
    recordDiagnosticReason(
      category: 'sql_stream_cancelled',
      reason: reason,
    );
  }

  void recordSqlStreamCancelFailed(String reason) {
    _incrementEventCounter(_rpcSqlStreamCancelFailedCounter);
    recordDiagnosticReason(
      category: 'sql_stream_cancel_failed',
      reason: reason,
    );
  }

  @override
  void recordSchemaValidation({
    required String direction,
    required String schemaId,
    required bool success,
    required Duration elapsed,
  }) {
    _incrementEventCounter(success ? _schemaValidationSuccessCounter : _schemaValidationFailureCounter);
    final key = '${direction.trim()}:${schemaId.trim()}';
    final elapsedUs = elapsed.inMicroseconds;
    _schemaValidationDurationUs += elapsedUs;
    _schemaValidationDurationUsByKey[key] = (_schemaValidationDurationUsByKey[key] ?? 0) + elapsedUs;
    _schemaValidationCountByKey[key] = (_schemaValidationCountByKey[key] ?? 0) + 1;
    if (!success) {
      _schemaValidationFailuresByKey[key] = (_schemaValidationFailuresByKey[key] ?? 0) + 1;
    }
  }

  @override
  void recordSchemaValidationSkippedLargePayload({
    required String direction,
  }) {
    _incrementEventCounter(_schemaValidationSkippedLargePayloadCounter);
    recordDiagnosticReason(
      category: 'schema_validation_skip',
      reason: '${direction.trim()}:large_payload',
    );
  }

  void recordPoolAcquireTimeout() => _incrementEventCounter(_poolAcquireTimeoutCounter);

  void recordSqlQueueWorkersEqualPool({
    required int workers,
    required int poolSize,
  }) {
    _incrementEventCounter(_sqlQueueWorkersEqualPoolCounter);
    developer.log(
      'SQL queue workers match ODBC pool size',
      name: 'metrics',
      level: 800,
      error: {
        'workers': workers,
        'pool_size': poolSize,
      },
    );
  }

  void recordConnectTimeout() => _incrementEventCounter(_connectTimeoutCounter);

  void recordQueryTimeout() => _incrementEventCounter(_queryTimeoutCounter);

  void recordOdbcQueryTimeoutByStage(String stage) {
    final normalizedStage = stage.trim().isEmpty ? 'unknown' : stage.trim();
    _odbcQueryTimeoutByStage[normalizedStage] = (_odbcQueryTimeoutByStage[normalizedStage] ?? 0) + 1;
  }

  void recordPreparedStatementReuse() {
    _incrementEventCounter(_preparedStatementReuseCounter);
    _incrementEventCounter(_preparedStatementCacheHitCounter);
  }

  void recordPreparedStatementCacheMiss() => _incrementEventCounter(_preparedStatementCacheMissCounter);

  void recordDiagnosticReason({
    required String category,
    required String reason,
  }) {
    final normalized = '${category.trim()}:${reason.trim()}';
    if (normalized == ':') {
      return;
    }
    _recentDiagnosticReasons.addLast(normalized);
    while (_recentDiagnosticReasons.length > _maxRecentDiagnosticReasons) {
      _recentDiagnosticReasons.removeFirst();
    }
  }

  void recordStreamCancelRequest() => _incrementEventCounter(_streamCancelRequestCounter);

  void recordStreamCancelBackpressure() => _incrementEventCounter(_streamCancelBackpressureCounter);

  void recordStreamCancelDisconnectFailure() => _incrementEventCounter(_streamCancelDisconnectFailureCounter);

  void recordStreamCancelDisconnectTimeout() => _incrementEventCounter(_streamCancelDisconnectTimeoutCounter);

  @override
  void recordAutoUpdateManualCheckStarted() => _incrementEventCounter(_autoUpdateManualCheckStartedCounter);

  @override
  void recordAutoUpdateManualCheckSuccessAvailable() =>
      _incrementEventCounter(_autoUpdateManualCheckSuccessAvailableCounter);

  @override
  void recordAutoUpdateManualCheckSuccessNotAvailable() =>
      _incrementEventCounter(_autoUpdateManualCheckSuccessNotAvailableCounter);

  @override
  void recordAutoUpdateManualCheckUpdaterError() => _incrementEventCounter(_autoUpdateManualCheckUpdaterErrorCounter);

  @override
  void recordAutoUpdateManualCheckTriggerTimeout() =>
      _incrementEventCounter(_autoUpdateManualCheckTriggerTimeoutCounter);

  @override
  void recordAutoUpdateManualCheckCompletionTimeout() =>
      _incrementEventCounter(_autoUpdateManualCheckCompletionTimeoutCounter);

  @override
  void recordAutoUpdateManualCheckTriggerFailure() =>
      _incrementEventCounter(_autoUpdateManualCheckTriggerFailureCounter);

  @override
  void recordAutoUpdateManualCheckNotInitialized() =>
      _incrementEventCounter(_autoUpdateManualCheckNotInitializedCounter);

  @override
  void recordAutoUpdateCircuitOpened() => _incrementEventCounter(_autoUpdateCircuitOpenedCounter);

  @override
  void recordAutoUpdateCircuitOpenRejected() => _incrementEventCounter(_autoUpdateCircuitOpenRejectedCounter);

  @override
  void recordAutoUpdateBackgroundCheckTriggerFailure() =>
      _incrementEventCounter(_autoUpdateBackgroundCheckTriggerFailureCounter);

  @override
  void recordAutoUpdateBackgroundCheckUpdaterError() =>
      _incrementEventCounter(_autoUpdateBackgroundCheckUpdaterErrorCounter);

  final ListQueue<Duration> _autoUpdateProbeTimes = ListQueue<Duration>();
  final ListQueue<Duration> _autoUpdateDownloadTimes = ListQueue<Duration>();

  @override
  void recordAutoUpdateProbeDuration(Duration duration) {
    if (duration.isNegative) return;
    _recordDurationSample(_autoUpdateProbeTimes, duration);
  }

  @override
  void recordAutoUpdateDownloadDuration(Duration duration) {
    if (duration.isNegative) return;
    _recordDurationSample(_autoUpdateDownloadTimes, duration);
  }

  /// Registra uma metrica de sucesso.
  void recordSuccess({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required int rowsAffected,
    required int columnCount,
  }) {
    final metric = QueryMetrics.success(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      rowsAffected: rowsAffected,
      columnCount: columnCount,
    );

    _addMetric(metric);
  }

  /// Registra uma metrica de falha.
  void recordFailure({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required String errorMessage,
  }) {
    final metric = QueryMetrics.failure(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      errorMessage: errorMessage,
    );

    _addMetric(metric);
  }

  @override
  MetricsSummary getSummary({int limit = 100}) {
    final recent = _metrics.length > limit ? _metrics.sublist(_metrics.length - limit) : _metrics;

    return MetricsSummary.fromList(recent);
  }

  /// Obtem metricas filtradas por sucesso/falha.
  List<QueryMetrics> getMetrics({bool? success}) {
    if (success == null) return List.unmodifiable(_metrics);

    return _metrics.where((m) => m.success == success).toList();
  }

  /// Obtem metricas acima de um tempo de execucao.
  List<QueryMetrics> getSlowQueries({
    Duration threshold = const Duration(seconds: 1),
  }) {
    return _metrics.where((m) => m.executionDuration > threshold).toList()
      ..sort((a, b) => b.executionDuration.compareTo(a.executionDuration));
  }

  /// Registra metrica e notifica listeners.
  void _addMetric(QueryMetrics metric) {
    _metrics.add(metric);
    if (_metrics.length > _maxMetrics) {
      _metrics.removeRange(0, _metrics.length - _maxMetrics);
    }

    if (!metric.success) {
      developer.log(
        'QueryMetric: ${metric.executionDuration.inMilliseconds}ms, '
        'rows: ${metric.rowsAffected}, success: false',
        name: 'metrics',
        level: 1000,
      );
    }

    if (!_metricsController.isClosed) {
      _metricsController.add(metric);
    }
  }

  void _incrementEventCounter(String counter) {
    _incrementEventCounterBy(counter, 1);
  }

  void _incrementEventCounterBy(String counter, int amount) {
    if (amount <= 0) {
      return;
    }
    _eventCounters[counter] = (_eventCounters[counter] ?? 0) + amount;
  }

  /// Exporta metricas para JSON.
  List<Map<String, dynamic>> exportToJson() {
    return _metrics.map((m) => m.toMap()).toList();
  }

  /// Gets a snapshot of current metrics for health/monitoring.
  @override
  Map<String, Object> getSnapshot() {
    final queryMetrics = _metrics.isNotEmpty ? _metrics : <QueryMetrics>[];
    final totalQueries = queryMetrics.length;
    final successfulQueries = queryMetrics.where((m) => m.success).length;
    final errorQueries = totalQueries - successfulQueries;

    // Calculate latencies
    final latencies = queryMetrics.map((m) => m.executionDuration.inMilliseconds).toList()..sort();

    final avgLatency = latencies.isNotEmpty ? latencies.reduce((a, b) => a + b) / latencies.length : 0.0;

    final p95Latency = latencies.isNotEmpty ? latencies[(latencies.length * 0.95).floor()] : 0;

    final p99Latency = latencies.isNotEmpty ? latencies[(latencies.length * 0.99).floor()] : 0;

    return {
      'query_count': totalQueries,
      'query_error_count': errorQueries,
      'query_avg_latency_ms': avgLatency,
      'query_p95_latency_ms': p95Latency,
      'query_p99_latency_ms': p99Latency,
      'sql_queue_rejection_count': sqlQueueRejectionCount,
      'sql_queue_timeout_count': sqlQueueTimeoutCount,
      'sql_queue_saturation_70_count': sqlQueueSaturation70Count,
      'sql_queue_saturation_90_count': sqlQueueSaturation90Count,
      'sql_queue_workers_equal_pool_count': sqlQueueWorkersEqualPoolCount,
      'pool_acquire_timeout_count': poolAcquireTimeoutCount,
      'direct_connection_active_count': _activeDirectConnections,
      'direct_connection_max_active_count': _maxActiveDirectConnections,
      'direct_connection_opened': _eventCounters['direct_connection_opened'] ?? 0,
      'direct_connection_closed': _eventCounters['direct_connection_closed'] ?? 0,
      'sql_queue_current_size': _currentQueueSize,
      'sql_queue_max_size': _maxQueueSize,
      'sql_queue_current_workers': _currentActiveWorkers,
      'sql_queue_max_workers': _maxActiveWorkers,
      'sql_queue_avg_wait_time_ms': _queueWaitTimes.isEmpty
          ? 0.0
          : _queueWaitTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / _queueWaitTimes.length,
      'sql_queue_p95_wait_time_ms': p95QueueWaitTime?.inMilliseconds ?? 0,
      'sql_queue_max_recent_wait_time_ms': maxRecentQueueWaitTime?.inMilliseconds ?? 0,
      ..._durationStatsSnapshot('agent_action_queue_wait', _agentActionQueueWaitTimes),
      ..._durationStatsSnapshot('agent_action_execution', _agentActionExecutionDurations),
      ..._durationStatsSnapshot('pool_wait', _poolWaitTimes),
      ..._durationStatsSnapshot('direct_connection_wait', _directConnectionWaitTimes),
      ..._durationStatsSnapshot('read_only_batch_parallel_wait', _readOnlyBatchParallelWaitTimes),
      ..._durationStatsSnapshot('connect', _connectTimes),
      ..._durationStatsSnapshot('sql_execution', _sqlExecutionTimes),
      ..._durationStatsSnapshot('auto_update_probe', _autoUpdateProbeTimes),
      ..._durationStatsSnapshot('auto_update_download', _autoUpdateDownloadTimes),
      ..._sqlExecutionModeStatsSnapshot(),
      'sql_execution_by_mode': _sqlExecutionModeNestedStatsSnapshot(),
      ..._durationStatsSnapshot('prepared_prepare', _preparedPrepareTimes),
      'rpc_sql_execute_db_streaming_skip_reasons': Map<String, int>.unmodifiable(_streamingSkipReasons),
      'odbc_native_fallback_reasons': Map<String, int>.unmodifiable(_odbcNativeFallbackReasons),
      'odbc_query_timeout_by_stage': Map<String, int>.unmodifiable(_odbcQueryTimeoutByStage),
      'schema_validation_duration_us': _schemaValidationDurationUs,
      'schema_validation_duration_by_schema_us': Map<String, int>.unmodifiable(_schemaValidationDurationUsByKey),
      'schema_validation_count_by_schema': Map<String, int>.unmodifiable(_schemaValidationCountByKey),
      'schema_validation_failure_by_schema': Map<String, int>.unmodifiable(_schemaValidationFailuresByKey),
      'read_only_batch_parallel_last_requested': _readOnlyBatchParallelLastRequested,
      'read_only_batch_parallel_last_effective': _readOnlyBatchParallelLastEffective,
      'recent_diagnostic_reasons': List<String>.unmodifiable(_recentDiagnosticReasons),
      'top_recent_diagnostic_reasons': _topRecentDiagnosticReasons(),
      ..._eventCounters,
    };
  }

  List<int> _sortedQueueWaitTimesMs() {
    return _queueWaitTimes.map((d) => d.inMilliseconds).toList()..sort();
  }

  void _recordDurationSample(ListQueue<Duration> samples, Duration value) {
    samples.addLast(value);
    if (samples.length > _maxWaitTimeSamples) {
      samples.removeFirst();
    }
  }

  void _recordTimestampSample(ListQueue<DateTime> samples, DateTime value) {
    samples.addLast(value);
    if (samples.length > _maxWaitTimeSamples) {
      samples.removeFirst();
    }
  }

  Map<String, Object> _durationStatsSnapshot(
    String prefix,
    Iterable<Duration> samples,
  ) {
    if (samples.isEmpty) {
      return {
        '${prefix}_avg_time_ms': 0.0,
        '${prefix}_p95_time_ms': 0,
        '${prefix}_p99_time_ms': 0,
        '${prefix}_max_recent_time_ms': 0,
        '${prefix}_sample_count': 0,
      };
    }

    final sorted = samples.map((d) => d.inMilliseconds).toList()..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    return {
      '${prefix}_avg_time_ms': total / sorted.length,
      '${prefix}_p95_time_ms': sorted[(sorted.length * 0.95).floor()],
      '${prefix}_p99_time_ms': sorted[(sorted.length * 0.99).floor()],
      '${prefix}_max_recent_time_ms': sorted.last,
      '${prefix}_sample_count': sorted.length,
    };
  }

  Map<String, Object> _sqlExecutionModeStatsSnapshot() {
    final values = <String, Object>{};
    for (final entry in _sqlExecutionTimesByMode.entries) {
      values.addAll(
        _durationStatsSnapshot(
          'sql_execution_${entry.key}',
          entry.value,
        ),
      );
    }
    return values;
  }

  Map<String, Object> _sqlExecutionModeNestedStatsSnapshot() {
    final values = <String, Object>{};
    for (final entry in _sqlExecutionTimesByMode.entries) {
      final stats = _durationStatsSnapshot('', entry.value);
      values[entry.key] = {
        'avg_time_ms': stats['_avg_time_ms'] ?? 0.0,
        'p95_time_ms': stats['_p95_time_ms'] ?? 0,
        'p99_time_ms': stats['_p99_time_ms'] ?? 0,
        'max_recent_time_ms': stats['_max_recent_time_ms'] ?? 0,
        'sample_count': entry.value.length,
        'ops_per_second': _opsPerSecondForMode(entry.key),
      };
    }
    return values;
  }

  double _opsPerSecondForMode(String mode) {
    final timestamps = _sqlExecutionTimestampsByMode[mode];
    if (timestamps == null || timestamps.isEmpty) {
      return 0;
    }
    if (timestamps.length == 1) {
      return 1;
    }
    final windowSeconds = timestamps.last.difference(timestamps.first).inMilliseconds / 1000;
    if (windowSeconds <= 0) {
      return timestamps.length.toDouble();
    }
    return timestamps.length / windowSeconds;
  }

  Map<String, int> _topRecentDiagnosticReasons() {
    final counts = <String, int>{};
    for (final reason in _recentDiagnosticReasons) {
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount == 0 ? a.key.compareTo(b.key) : byCount;
      });
    return Map<String, int>.fromEntries(entries.take(10));
  }

  /// Dispose do controller.
  void dispose() {
    _metricsController.close();
  }
}
