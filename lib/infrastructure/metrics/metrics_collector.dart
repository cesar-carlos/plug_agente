import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/action_execution_queue_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_schema_validation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';

part 'metrics_collector_auth_domain.dart';
part 'metrics_collector_odbc_domain.dart';
part 'metrics_collector_protocol_domain.dart';

/// Servico para coletar e gerenciar metricas de performance.
///
/// Chaves em [_eventCounters] sao estaveis para exportacao (ex.: OpenTelemetry).
final class MetricsCollector extends MetricsCollectorCore
    with MetricsCollectorAuthDomain, MetricsCollectorOdbcDomain, MetricsCollectorProtocolDomain
    implements
        IMetricsCollector,
        IAutoUpdateMetricsCollector,
        ISchemaValidationMetricsCollector,
        SqlExecutionQueueMetricsCollector,
        ActionExecutionQueueMetricsCollector,
        AgentActionExecutionMetricsCollector {
  MetricsCollector();
}

/// Shared metrics state and cross-domain recording helpers.
class MetricsCollectorCore {
  MetricsCollectorCore();

  static const String timeoutCancelSuccessCounter = 'timeout_cancel_success';
  static const String timeoutCancelFailureCounter = 'timeout_cancel_failure';
  static const String transactionRollbackFailureCounter = 'transaction_rollback_failure';
  static const String transactionRollbackAttemptCounter = 'transaction_rollback_attempt';
  static const String idempotencyFingerprintMismatchCounter = 'idempotency_fingerprint_mismatch';
  static const String multiResultPoolVacuousFallbackCounter = 'multi_result_pool_vacuous_fallback';
  static const String multiResultDirectStillVacuousCounter = 'multi_result_direct_still_vacuous';
  static const String transactionalBatchDirectPathCounter = 'transactional_batch_direct_path';
  static const String transactionalBatchNativePoolPathCounter = 'transactional_batch_native_pool_path';
  static const String transactionalBatchNativePoolFallbackCounter = 'transactional_batch_native_pool_fallback';
  static const String batchBulkInsertRecommendedCounter = 'batch_bulk_insert_recommended';
  static const String batchBulkInsertRoutedCounter = 'batch_bulk_insert_routed';
  static const String directConnectionFallbackCounter = 'direct_connection_fallback';
  static const String odbcNativePoolFallbackCounter = 'odbc_native_pool_fallback';
  static const String odbcNativeFallbackTotalCounter = 'odbc_native_fallback_total';
  static const String odbcNativePoolOptionsSkipCounter = 'odbc_native_pool_options_skip';
  static const String odbcNativeCircuitOpenedCounter = 'odbc_native_circuit_opened_total';
  static const String odbcBufferExpansionCounter = 'odbc_buffer_expansion_total';
  static const String odbcInvalidConnectionRecycleCounter = 'odbc_invalid_connection_recycle_total';
  static const String odbcNativeCompatibleAcquireAttemptCounter = 'odbc_native_compatible_acquire_attempt';
  static const String odbcNativeCompatibleAcquireSuccessCounter = 'odbc_native_compatible_acquire_success';
  static const String readOnlyBatchParallelCounter = 'read_only_batch_parallel';
  static const String readOnlyBatchParallelCappedCounter = 'read_only_batch_parallel_capped';
  static const String readOnlyBatchNativePoolPathCounter = 'read_only_batch_native_pool_path';
  static const String readOnlyBatchNativePoolFallbackCounter = 'read_only_batch_native_pool_fallback';
  static const String directConnectionAcquireTimeoutCounter = 'direct_connection_acquire_timeout';
  static const String poolReleaseFailureCounter = 'pool_release_failure';
  static const String poolDiscardInflightCounter = 'pool_discard_inflight';
  static const String poolDiscardReconciliationStaleCounter = 'pool_discard_reconciliation_stale';
  static const String poolDiscardReconciliationRemediatedCounter = 'pool_discard_reconciliation_remediated';
  static const String poolDiscardReconciliationForceReleaseCounter = 'pool_discard_reconciliation_force_release';
  static const String bulkInsertChunkedCounter = 'bulk_insert_chunked_total';
  static const String bulkInsertParallelCounter = 'bulk_insert_parallel_total';
  static const String poolRecycleCounter = 'pool_recycle';
  static const String poolRecycleFailureCounter = 'pool_recycle_failure';
  static const String odbcEventConnectionLostCounter = 'odbc_event_connection_lost';
  static const String odbcEventAutoReconnectAttemptedCounter = 'odbc_event_auto_reconnect_attempted';
  static const String odbcEventWorkerRecoveredCounter = 'odbc_event_worker_recovered';
  static const String odbcEventPoolResizeCounter = 'odbc_event_pool_resize';
  static const String odbcEventSlowQueryDetectedCounter = 'odbc_event_slow_query_detected';
  static const String transactionalBatchReadOnlyInferenceCounter = 'transactional_batch_readonly_inference';
  static const String transactionalBatchDeadlineNearStallCounter = 'transactional_batch_deadline_near_stall';
  static const String authDecisionCacheHitCounter = 'auth_decision_cache_hit';
  static const String authDecisionCacheMissCounter = 'auth_decision_cache_miss';
  static const String authPolicyCacheHitCounter = 'auth_policy_cache_hit';
  static const String authPolicyCacheMissCounter = 'auth_policy_cache_miss';
  static const String rpcSqlExecuteStreamingChunksResponseCounter = 'rpc_sql_execute_streaming_chunks_response';
  static const String rpcSqlExecuteStreamingFromDbResponseCounter = 'rpc_sql_execute_streaming_from_db_response';
  static const String rpcSqlExecuteAutoStreamingFromDbResponseCounter =
      'rpc_sql_execute_auto_streaming_from_db_response';
  static const String rpcSqlExecutePreferDbStreamingResponseCounter = 'rpc_sql_execute_prefer_db_streaming_response';
  static const String rpcSqlExecuteAllowlistDbStreamingResponseCounter =
      'rpc_sql_execute_allowlist_db_streaming_response';
  static const String rpcSqlExecuteDbStreamingSkipCounter = 'rpc_sql_execute_db_streaming_skip';
  static const String rpcSqlExecuteMaterializedResponseCounter = 'rpc_sql_execute_materialized_response';
  static const String rpcStreamTerminalCompleteEmittedCounter = 'rpc_stream_terminal_complete_emitted';
  static const String rpcStreamTerminalCompleteFailedCounter = 'rpc_stream_terminal_complete_failed';
  static const String rpcResponseAckRetryCounter = 'rpc_response_ack_retry';
  static const String rpcResponseAckDeliveredCounter = 'rpc_response_ack_delivered';
  static const String rpcResponseAckAbortedConnectionChangeCounter = 'rpc_response_ack_aborted_connection_change';
  static const String rpcResponseAckFallbackWithoutAckCounter = 'rpc_response_ack_fallback_without_ack';
  static const String rpcResponseAckSkippedSqlExecuteCounter = 'rpc_response_ack_skipped_sql_execute';
  static const String rpcResponseAckSkippedSqlExecuteBatchCounter = 'rpc_response_ack_skipped_sql_execute_batch';
  static const String rpcClientTokenGetPolicySuccessCounter = 'rpc_client_token_get_policy_success';
  static const String rpcClientTokenGetPolicyFailureCounter = 'rpc_client_token_get_policy_failure';
  static const String rpcClientTokenGetPolicyFailureValidationCounter =
      'rpc_client_token_get_policy_failure_validation';
  static const String rpcClientTokenGetPolicyFailureNetworkCounter = 'rpc_client_token_get_policy_failure_network';
  static const String rpcClientTokenGetPolicyFailureServerCounter = 'rpc_client_token_get_policy_failure_server';
  static const String rpcClientTokenGetPolicyFailureNotFoundCounter = 'rpc_client_token_get_policy_failure_not_found';
  static const String rpcClientTokenGetPolicyFailureConnectionCounter =
      'rpc_client_token_get_policy_failure_connection';
  static const String rpcClientTokenGetPolicyFailureDatabaseCounter = 'rpc_client_token_get_policy_failure_database';
  static const String rpcClientTokenGetPolicyFailureConfigurationCounter =
      'rpc_client_token_get_policy_failure_configuration';
  static const String rpcClientTokenGetPolicyFailureQueryCounter = 'rpc_client_token_get_policy_failure_query';
  static const String rpcClientTokenGetPolicyFailureCompressionCounter =
      'rpc_client_token_get_policy_failure_compression';
  static const String rpcClientTokenGetPolicyFailureNotificationCounter =
      'rpc_client_token_get_policy_failure_notification';
  static const String rpcClientTokenGetPolicyFailureOtherCounter = 'rpc_client_token_get_policy_failure_other';
  static const String rpcClientTokenGetPolicyRateLimitedCounter = 'rpc_client_token_get_policy_rate_limited';
  static const String rpcRemoteAgentActionRunSuccessCounter = 'rpc_remote_agent_action_run_success';
  static const String rpcRemoteAgentActionRunErrorCounter = 'rpc_remote_agent_action_run_error';
  static const String rpcRemoteAgentActionValidateRunSuccessCounter = 'rpc_remote_agent_action_validate_run_success';
  static const String rpcRemoteAgentActionValidateRunErrorCounter = 'rpc_remote_agent_action_validate_run_error';
  static const String rpcRemoteAgentActionCancelSuccessCounter = 'rpc_remote_agent_action_cancel_success';
  static const String rpcRemoteAgentActionCancelErrorCounter = 'rpc_remote_agent_action_cancel_error';
  static const String agentActionQueueConcurrencyRejectCounter = 'agent_action_queue_concurrency_reject';
  static const String agentActionQueueConcurrencyIgnoreCounter = 'agent_action_queue_concurrency_ignore';
  static const String agentActionQueueDepthFullCounter = 'agent_action_queue_depth_full';
  static const String agentActionQueuePendingEnqueuedCounter = 'agent_action_queue_pending_enqueued';
  static const String agentActionQueueIdempotentReplayCounter = 'agent_action_queue_idempotent_replay';
  static const String agentActionQueueRunStartedCounter = 'agent_action_queue_run_started';
  static const String agentActionQueuePendingWaitTimeoutCounter = 'agent_action_queue_pending_wait_timeout';
  static const String agentActionQueuePendingCancelledCounter = 'agent_action_queue_pending_cancelled';
  static const String agentActionExecutionTerminalSucceededCounter = 'agent_action_execution_terminal_succeeded';
  static const String agentActionExecutionTerminalFailedCounter = 'agent_action_execution_terminal_failed';
  static const String agentActionExecutionTerminalSkippedCounter = 'agent_action_execution_terminal_skipped';
  static const String agentActionExecutionTerminalCancelledCounter = 'agent_action_execution_terminal_cancelled';
  static const String agentActionExecutionTerminalKilledCounter = 'agent_action_execution_terminal_killed';
  static const String agentActionExecutionTerminalTimedOutCounter = 'agent_action_execution_terminal_timed_out';
  static const String agentActionExecutionTerminalInterruptedCounter = 'agent_action_execution_terminal_interrupted';
  static const String agentActionExecutionTerminalUnknownCounter = 'agent_action_execution_terminal_unknown';
  static const String agentActionRemotePermissionDeniedCounter = 'agent_action_remote_permission_denied';
  static const String agentActionLocalAuthorizationDeniedCounter = 'agent_action_local_authorization_denied';
  static const String agentActionRemoteRateLimitedCounter = 'agent_action_remote_rate_limited';
  static const String agentActionExecutionHistoryPurgeCounter = 'agent_action_execution_history_purge';
  static const String agentActionRemoteAuditPurgeCounter = 'agent_action_remote_audit_purge';
  static const String agentActionRpcIdempotencyCachePurgeCounter = 'agent_action_rpc_idempotency_cache_purge';
  static const String agentActionElevatedBridgeArtifactsPurgeCounter = 'agent_action_elevated_bridge_artifacts_purge';
  static const String agentActionRemoteAuditExecutionCorrelatedCounter =
      'agent_action_remote_audit_execution_correlated';
  static const String agentActionCancelKillFailedCounter = 'agent_action_cancel_kill_failed';
  static const String agentActionCancelKillPermissionDeniedCounter = 'agent_action_cancel_kill_permission_denied';
  static const String agentActionCancelProcessNotActiveCounter = 'agent_action_cancel_process_not_active';
  static const String agentActionCancelProcessIdMismatchCounter = 'agent_action_cancel_process_id_mismatch';
  static const String agentActionCancelProcessIdentityMismatchCounter =
      'agent_action_cancel_process_identity_mismatch';
  static const String agentActionCancelProcessIdentityUnavailableCounter =
      'agent_action_cancel_process_identity_unavailable';
  static const String agentActionCapturedStdoutTruncatedCounter = 'agent_action_captured_output_stdout_truncated';
  static const String agentActionCapturedStderrTruncatedCounter = 'agent_action_captured_output_stderr_truncated';
  static const String agentActionCapturedStdoutBytesCounter = 'agent_action_captured_output_stdout_bytes';
  static const String agentActionCapturedStderrBytesCounter = 'agent_action_captured_output_stderr_bytes';
  static const String agentActionCapturedOutputClearedCounter = 'agent_action_captured_output_cleared';
  static const String agentActionElevatedStatusFileTerminalCounter = 'agent_action_elevated_status_file_terminal';
  static const String agentActionElevatedStatusFileWaitTimeoutCounter =
      'agent_action_elevated_status_file_wait_timeout';
  static const String rpcRemoteAgentActionGetExecutionSuccessCounter = 'rpc_remote_agent_action_get_execution_success';
  static const String rpcRemoteAgentActionGetExecutionErrorCounter = 'rpc_remote_agent_action_get_execution_error';
  static const String rpcRemoteAgentActionRunNotificationRejectedCounter =
      'rpc_remote_agent_action_run_notification_rejected';
  static const String rpcRemoteAgentActionValidateRunNotificationRejectedCounter =
      'rpc_remote_agent_action_validate_run_notification_rejected';
  static const String rpcRemoteAgentActionCancelNotificationRejectedCounter =
      'rpc_remote_agent_action_cancel_notification_rejected';
  static const String rpcRemoteAgentActionGetExecutionNotificationRejectedCounter =
      'rpc_remote_agent_action_get_execution_notification_rejected';
  static const String rpcRemoteAgentActionBatchReadLimitRejectedCounter =
      'rpc_remote_agent_action_batch_read_limit_rejected';
  static const String rpcMethodConcurrencyLimitedCounter = 'rpc_method_concurrency_limited';
  static const String rpcSqlStreamCancelledCounter = 'rpc_sql_stream_cancelled';
  static const String rpcSqlStreamCancelFailedCounter = 'rpc_sql_stream_cancel_failed';
  static const String schemaValidationSuccessCounter = 'schema_validation_success_total';
  static const String schemaValidationFailureCounter = 'schema_validation_failure_total';
  static const String schemaValidationSkippedLargePayloadCounter = 'schema_validation_skipped_large_payload_total';
  static const String poolAcquireTimeoutCounter = 'pool_acquire_timeout';
  static const String connectTimeoutCounter = 'connect_timeout';
  static const String queryTimeoutCounter = 'query_timeout';
  static const String preparedStatementReuseCounter = 'prepared_statement_reuse';
  static const String preparedStatementCacheHitCounter = 'prepared_statement_cache_hit';
  static const String preparedStatementCacheMissCounter = 'prepared_statement_cache_miss';
  static const String streamCancelRequestCounter = 'stream_cancel_request';
  static const String streamCancelBackpressureCounter = 'stream_cancel_backpressure';
  static const String streamCancelDisconnectFailureCounter = 'stream_cancel_disconnect_failure';
  static const String streamCancelDisconnectTimeoutCounter = 'stream_cancel_disconnect_timeout';
  static const String sqlQueueRejectionCounter = 'sql_queue_rejection';
  static const String sqlQueueTimeoutCounter = 'sql_queue_timeout';
  static const String sqlQueueTimeoutAfterWorkerStartedCounter =
      'sql_queue_timeout_after_worker_started';
  static const String sqlQueueSaturation70Counter = 'sql_queue_saturation_70';
  static const String sqlQueueSaturation90Counter = 'sql_queue_saturation_90';
  static const String sqlQueueWorkersEqualPoolCounter = 'sql_queue_workers_equal_pool';
  static const String streamingBatchedPathCounter = 'streaming_batched_path';
  static const String streamingSingleChunkPathCounter = 'streaming_single_chunk_path';
  static const String autoUpdateManualCheckStartedCounter = 'auto_update_manual_check_started';
  static const String autoUpdateManualCheckSuccessAvailableCounter = 'auto_update_manual_check_success_available';
  static const String autoUpdateManualCheckSuccessNotAvailableCounter =
      'auto_update_manual_check_success_not_available';
  static const String autoUpdateManualCheckUpdaterErrorCounter = 'auto_update_manual_check_updater_error';
  static const String autoUpdateManualCheckTriggerTimeoutCounter = 'auto_update_manual_check_trigger_timeout';
  static const String autoUpdateManualCheckCompletionTimeoutCounter = 'auto_update_manual_check_completion_timeout';
  static const String autoUpdateManualCheckTriggerFailureCounter = 'auto_update_manual_check_trigger_failure';
  static const String autoUpdateManualCheckNotInitializedCounter = 'auto_update_manual_check_not_initialized';
  static const String autoUpdateCircuitOpenedCounter = 'auto_update_circuit_opened';
  static const String autoUpdateCircuitOpenRejectedCounter = 'auto_update_circuit_open_rejected';
  static const String autoUpdateBackgroundCheckTriggerFailureCounter = 'auto_update_background_check_trigger_failure';
  static const String autoUpdateBackgroundCheckUpdaterErrorCounter = 'auto_update_background_check_updater_error';
  static const String autoUpdateAwaitingUserConsentCounter = 'auto_update_awaiting_user_consent';
  static const String autoUpdateUserInitiatedApplySuccessCounter = 'auto_update_user_initiated_apply_success';
  static const String autoUpdateUserInitiatedApplyFailureCounter = 'auto_update_user_initiated_apply_failure';
  static const String autoUpdateNotificationsPreferenceEnabledCounter =
      'auto_update_notifications_preference_enabled';
  static const String autoUpdateNotificationsPreferenceDisabledCounter =
      'auto_update_notifications_preference_disabled';
  static const String autoUpdateAutomaticSilentPreferenceEnabledCounter =
      'auto_update_automatic_silent_preference_enabled';
  static const String autoUpdateAutomaticSilentPreferenceDisabledCounter =
      'auto_update_automatic_silent_preference_disabled';
  static const String autoUpdateManualOnlyModeAppliedCounter = 'auto_update_manual_only_mode_applied';

  static const int _maxMetrics = 10000;

  // ListQueue keeps `_addMetric` O(1) at the ring-buffer cap. Using a plain
  // List forced `removeRange(0, 1)` on every add at cap, which is O(n) and
  // amplifies into millions of element shifts per second under sustained QPS.
  final ListQueue<QueryMetrics> _metrics = ListQueue<QueryMetrics>();
  final _metricsController = StreamController<QueryMetrics>.broadcast();
  final Map<String, int> _eventCounters = <String, int>{};
  int _activeDirectConnections = 0;
  int _maxActiveDirectConnections = 0;
  int _poolDiscardInflight = 0;
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
  final ListQueue<Duration> _streamingWorkerHoldTimes = ListQueue<Duration>();
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

  Stream<QueryMetrics> get metricsStream => _metricsController.stream;

  List<QueryMetrics> get metrics => List.unmodifiable(_metrics);

  /// Numero de metricas coletadas.
  int get count => _metrics.length;
  int get sqlQueueRejectionCount => _eventCounters[sqlQueueRejectionCounter] ?? 0;
  int get sqlQueueTimeoutCount => _eventCounters[sqlQueueTimeoutCounter] ?? 0;
  int get sqlQueueTimeoutAfterWorkerStartedCount =>
      _eventCounters[sqlQueueTimeoutAfterWorkerStartedCounter] ?? 0;
  int get sqlQueueSaturation70Count => _eventCounters[sqlQueueSaturation70Counter] ?? 0;
  int get sqlQueueSaturation90Count => _eventCounters[sqlQueueSaturation90Counter] ?? 0;
  int get sqlQueueWorkersEqualPoolCount => _eventCounters[sqlQueueWorkersEqualPoolCounter] ?? 0;
  int get autoUpdateManualCheckStartedCount => _eventCounters[autoUpdateManualCheckStartedCounter] ?? 0;
  int get autoUpdateManualCheckSuccessAvailableCount =>
      _eventCounters[autoUpdateManualCheckSuccessAvailableCounter] ?? 0;
  int get autoUpdateManualCheckSuccessNotAvailableCount =>
      _eventCounters[autoUpdateManualCheckSuccessNotAvailableCounter] ?? 0;
  int get autoUpdateManualCheckUpdaterErrorCount => _eventCounters[autoUpdateManualCheckUpdaterErrorCounter] ?? 0;
  int get autoUpdateManualCheckTriggerTimeoutCount => _eventCounters[autoUpdateManualCheckTriggerTimeoutCounter] ?? 0;
  int get autoUpdateManualCheckCompletionTimeoutCount =>
      _eventCounters[autoUpdateManualCheckCompletionTimeoutCounter] ?? 0;
  int get autoUpdateManualCheckTriggerFailureCount => _eventCounters[autoUpdateManualCheckTriggerFailureCounter] ?? 0;
  int get autoUpdateManualCheckNotInitializedCount => _eventCounters[autoUpdateManualCheckNotInitializedCounter] ?? 0;
  int get autoUpdateCircuitOpenedCount => _eventCounters[autoUpdateCircuitOpenedCounter] ?? 0;
  int get autoUpdateCircuitOpenRejectedCount => _eventCounters[autoUpdateCircuitOpenRejectedCounter] ?? 0;
  int get autoUpdateBackgroundCheckTriggerFailureCount =>
      _eventCounters[autoUpdateBackgroundCheckTriggerFailureCounter] ?? 0;
  int get autoUpdateBackgroundCheckUpdaterErrorCount =>
      _eventCounters[autoUpdateBackgroundCheckUpdaterErrorCounter] ?? 0;
  int get autoUpdateAwaitingUserConsentCount => _eventCounters[autoUpdateAwaitingUserConsentCounter] ?? 0;
  int get autoUpdateUserInitiatedApplySuccessCount => _eventCounters[autoUpdateUserInitiatedApplySuccessCounter] ?? 0;
  int get autoUpdateUserInitiatedApplyFailureCount => _eventCounters[autoUpdateUserInitiatedApplyFailureCounter] ?? 0;
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
    _streamingWorkerHoldTimes.clear();
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

  void recordQueueAdded(int currentSize) {
    recordQueueSizeChanged(currentSize);
  }

  void recordQueueSizeChanged(int currentSize) {
    _currentQueueSize = currentSize;
    if (currentSize > _maxQueueSize) {
      _maxQueueSize = currentSize;
    }
  }

  void recordQueueRejection() {
    _incrementEventCounter(sqlQueueRejectionCounter);
  }

  void recordQueueTimeout() {
    _incrementEventCounter(sqlQueueTimeoutCounter);
  }

  void recordQueueTimeoutAfterWorkerStarted() {
    _incrementEventCounter(sqlQueueTimeoutAfterWorkerStartedCounter);
    final count = sqlQueueTimeoutAfterWorkerStartedCount;
    recordDiagnosticReason(category: 'sql_queue', reason: 'ghost_query_risk');
    if (count == 1 || count % 5 == 0) {
      developer.log(
        'SQL queue timeout after worker started — ghost query risk (in-flight ODBC may continue)',
        name: 'metrics',
        level: 900,
        error: {
          'ghost_query_risk': true,
          'sql_queue_timeout_after_worker_started_count': count,
        },
      );
    }
  }

  void recordQueueSaturation({required int thresholdPercent, required int currentSize, required int maxSize}) {
    final counter = switch (thresholdPercent) {
      70 => sqlQueueSaturation70Counter,
      90 => sqlQueueSaturation90Counter,
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

  void recordQueueWaitTime(Duration waitTime) {
    _recordDurationSample(_queueWaitTimes, waitTime);
  }

  void recordConcurrencyReject() {
    _incrementEventCounter(agentActionQueueConcurrencyRejectCounter);
  }

  void recordConcurrencyIgnore() {
    _incrementEventCounter(agentActionQueueConcurrencyIgnoreCounter);
  }

  void recordQueueDepthFull() {
    _incrementEventCounter(agentActionQueueDepthFullCounter);
  }

  void recordPendingEnqueued() {
    _incrementEventCounter(agentActionQueuePendingEnqueuedCounter);
  }

  void recordIdempotentReplay() {
    _incrementEventCounter(agentActionQueueIdempotentReplayCounter);
  }

  void recordRunStarted() {
    _incrementEventCounter(agentActionQueueRunStartedCounter);
  }

  void recordPendingWaitTimeout() {
    _incrementEventCounter(agentActionQueuePendingWaitTimeoutCounter);
  }

  void recordPendingCancelled() {
    _incrementEventCounter(agentActionQueuePendingCancelledCounter);
  }

  void recordPendingDequeueWaitTime(Duration wait) {
    _recordDurationSample(_agentActionQueueWaitTimes, wait);
  }

  void recordTerminalOutcome(AgentActionExecutionStatus status) {
    final counter = switch (status) {
      AgentActionExecutionStatus.succeeded => agentActionExecutionTerminalSucceededCounter,
      AgentActionExecutionStatus.failed => agentActionExecutionTerminalFailedCounter,
      AgentActionExecutionStatus.skipped => agentActionExecutionTerminalSkippedCounter,
      AgentActionExecutionStatus.cancelled => agentActionExecutionTerminalCancelledCounter,
      AgentActionExecutionStatus.killed => agentActionExecutionTerminalKilledCounter,
      AgentActionExecutionStatus.timedOut => agentActionExecutionTerminalTimedOutCounter,
      AgentActionExecutionStatus.interrupted => agentActionExecutionTerminalInterruptedCounter,
      AgentActionExecutionStatus.unknown => agentActionExecutionTerminalUnknownCounter,
      AgentActionExecutionStatus.queued || AgentActionExecutionStatus.running => null,
    };
    if (counter != null) {
      _incrementEventCounter(counter);
    }
  }

  void recordExecutionDuration(Duration duration) {
    if (duration.isNegative) {
      return;
    }
    _recordDurationSample(_agentActionExecutionDurations, duration);
  }

  void recordRemotePermissionDenied() {
    _incrementEventCounter(agentActionRemotePermissionDeniedCounter);
  }

  void recordLocalAuthorizationDenied() {
    _incrementEventCounter(agentActionLocalAuthorizationDeniedCounter);
  }

  void recordRemoteRateLimited() {
    _incrementEventCounter(agentActionRemoteRateLimitedCounter);
  }

  void recordExecutionHistoryPurge(int removedCount) {
    _incrementEventCounterBy(agentActionExecutionHistoryPurgeCounter, removedCount);
  }

  void recordRemoteAuditPurge(int removedCount) {
    _incrementEventCounterBy(agentActionRemoteAuditPurgeCounter, removedCount);
  }

  void recordRpcIdempotencyCachePurge(int removedCount) {
    _incrementEventCounterBy(agentActionRpcIdempotencyCachePurgeCounter, removedCount);
  }

  void recordElevatedBridgeArtifactsPurge(int removedCount) {
    _incrementEventCounterBy(agentActionElevatedBridgeArtifactsPurgeCounter, removedCount);
  }

  void recordRemoteAuditExecutionCorrelated() {
    _incrementEventCounter(agentActionRemoteAuditExecutionCorrelatedCounter);
  }

  void recordCancelKillFailed() {
    _incrementEventCounter(agentActionCancelKillFailedCounter);
  }

  void recordCancelKillPermissionDenied() {
    _incrementEventCounter(agentActionCancelKillPermissionDeniedCounter);
  }

  void recordCancelProcessNotActive() {
    _incrementEventCounter(agentActionCancelProcessNotActiveCounter);
  }

  void recordCancelProcessIdMismatch() {
    _incrementEventCounter(agentActionCancelProcessIdMismatchCounter);
  }

  void recordCancelProcessIdentityMismatch() {
    _incrementEventCounter(agentActionCancelProcessIdentityMismatchCounter);
  }

  void recordCancelProcessIdentityUnavailable() {
    _incrementEventCounter(agentActionCancelProcessIdentityUnavailableCounter);
  }

  void recordCapturedOutputPersisted({
    required bool stdoutCaptured,
    required bool stderrCaptured,
    required bool stdoutTruncated,
    required bool stderrTruncated,
    int stdoutUtf8Bytes = 0,
    int stderrUtf8Bytes = 0,
  }) {
    if (stdoutCaptured && stdoutTruncated) {
      _incrementEventCounter(agentActionCapturedStdoutTruncatedCounter);
    }
    if (stderrCaptured && stderrTruncated) {
      _incrementEventCounter(agentActionCapturedStderrTruncatedCounter);
    }
    _incrementEventCounterBy(agentActionCapturedStdoutBytesCounter, stdoutUtf8Bytes);
    _incrementEventCounterBy(agentActionCapturedStderrBytesCounter, stderrUtf8Bytes);
  }

  void recordCapturedOutputCleared(int executionCount) {
    _incrementEventCounterBy(agentActionCapturedOutputClearedCounter, executionCount);
  }

  void recordElevatedStatusFileTerminalRead() {
    _incrementEventCounter(agentActionElevatedStatusFileTerminalCounter);
  }

  void recordElevatedStatusFileWaitTimeout() {
    _incrementEventCounter(agentActionElevatedStatusFileWaitTimeoutCounter);
  }

  void recordWorkerStarted(int activeCount) {
    _currentActiveWorkers = activeCount;
    if (activeCount > _maxActiveWorkers) {
      _maxActiveWorkers = activeCount;
    }
  }

  void recordWorkerCompleted(int activeCount) {
    _currentActiveWorkers = activeCount;
  }

  void recordStreamingWorkerHoldTime(Duration holdTime) {
    if (holdTime.isNegative) {
      return;
    }
    _recordDurationSample(_streamingWorkerHoldTimes, holdTime);
  }

  void recordSqlQueueWorkersEqualPool({
    required int workers,
    required int poolSize,
  }) {
    _incrementEventCounter(sqlQueueWorkersEqualPoolCounter);
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

  void recordAutoUpdateManualCheckStarted() => _incrementEventCounter(autoUpdateManualCheckStartedCounter);

  void recordAutoUpdateManualCheckSuccessAvailable() =>
      _incrementEventCounter(autoUpdateManualCheckSuccessAvailableCounter);

  void recordAutoUpdateManualCheckSuccessNotAvailable() =>
      _incrementEventCounter(autoUpdateManualCheckSuccessNotAvailableCounter);

  void recordAutoUpdateManualCheckUpdaterError() => _incrementEventCounter(autoUpdateManualCheckUpdaterErrorCounter);

  void recordAutoUpdateManualCheckTriggerTimeout() =>
      _incrementEventCounter(autoUpdateManualCheckTriggerTimeoutCounter);

  void recordAutoUpdateManualCheckCompletionTimeout() =>
      _incrementEventCounter(autoUpdateManualCheckCompletionTimeoutCounter);

  void recordAutoUpdateManualCheckTriggerFailure() =>
      _incrementEventCounter(autoUpdateManualCheckTriggerFailureCounter);

  void recordAutoUpdateManualCheckNotInitialized() =>
      _incrementEventCounter(autoUpdateManualCheckNotInitializedCounter);

  void recordAutoUpdateCircuitOpened() => _incrementEventCounter(autoUpdateCircuitOpenedCounter);

  void recordAutoUpdateCircuitOpenRejected() => _incrementEventCounter(autoUpdateCircuitOpenRejectedCounter);

  void recordAutoUpdateBackgroundCheckTriggerFailure() =>
      _incrementEventCounter(autoUpdateBackgroundCheckTriggerFailureCounter);

  void recordAutoUpdateBackgroundCheckUpdaterError() =>
      _incrementEventCounter(autoUpdateBackgroundCheckUpdaterErrorCounter);

  void recordAutoUpdateNotificationsPreferenceEnabled() =>
      _incrementEventCounter(autoUpdateNotificationsPreferenceEnabledCounter);

  void recordAutoUpdateNotificationsPreferenceDisabled() =>
      _incrementEventCounter(autoUpdateNotificationsPreferenceDisabledCounter);

  void recordAutoUpdateAutomaticSilentPreferenceEnabled() =>
      _incrementEventCounter(autoUpdateAutomaticSilentPreferenceEnabledCounter);

  void recordAutoUpdateAutomaticSilentPreferenceDisabled() =>
      _incrementEventCounter(autoUpdateAutomaticSilentPreferenceDisabledCounter);

  void recordAutoUpdateManualOnlyModeApplied() =>
      _incrementEventCounter(autoUpdateManualOnlyModeAppliedCounter);

  final ListQueue<Duration> _autoUpdateProbeTimes = ListQueue<Duration>();
  final ListQueue<Duration> _autoUpdateDownloadTimes = ListQueue<Duration>();

  void recordAutoUpdateProbeDuration(Duration duration) {
    if (duration.isNegative) return;
    _recordDurationSample(_autoUpdateProbeTimes, duration);
  }

  void recordAutoUpdateDownloadDuration(Duration duration) {
    if (duration.isNegative) return;
    _recordDurationSample(_autoUpdateDownloadTimes, duration);
  }

  void recordAutoUpdateAwaitingUserConsent() => _incrementEventCounter(autoUpdateAwaitingUserConsentCounter);

  void recordAutoUpdateUserInitiatedApplySuccess() =>
      _incrementEventCounter(autoUpdateUserInitiatedApplySuccessCounter);

  void recordAutoUpdateUserInitiatedApplyFailure() =>
      _incrementEventCounter(autoUpdateUserInitiatedApplyFailureCounter);

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

  MetricsSummary getSummary({int limit = 100}) {
    final List<QueryMetrics> recent;
    if (_metrics.length > limit) {
      recent = _metrics.skip(_metrics.length - limit).toList(growable: false);
    } else {
      recent = _metrics.toList(growable: false);
    }
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
    _metrics.addLast(metric);
    while (_metrics.length > _maxMetrics) {
      _metrics.removeFirst();
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
      'sql_queue_timeout_after_worker_started_count': sqlQueueTimeoutAfterWorkerStartedCount,
      'sql_queue_saturation_70_count': sqlQueueSaturation70Count,
      'sql_queue_saturation_90_count': sqlQueueSaturation90Count,
      'sql_queue_workers_equal_pool_count': sqlQueueWorkersEqualPoolCount,
      'pool_acquire_timeout_count': _eventCounters[poolAcquireTimeoutCounter] ?? 0,
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
      ..._durationStatsSnapshot('streaming_worker_hold', _streamingWorkerHoldTimes),
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
