/// Stable counter keys for metrics export (OpenTelemetry, agent.getHealth).
abstract final class MetricsCounterNames {
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
  static const String odbcWorkerRecoveryInvalidationCounter = 'odbc_worker_recovery_invalidation';
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
  static const String rpcResponseEmitFailureCounter = 'rpc_response_emit_failure';
  static const String rpcResponseEmitSkippedDisconnectedCounter = 'rpc_response_emit_skipped_disconnected';
  static const String rpcStreamPullInvalidCounter = 'rpc_stream_pull_invalid';
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
  static const String sqlQueueTimeoutAfterWorkerStartedCounter = 'sql_queue_timeout_after_worker_started';
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
  static const String autoUpdateAutomaticApplySuccessCounter = 'auto_update_automatic_apply_success';
  static const String autoUpdateAutomaticApplyFailureCounter = 'auto_update_automatic_apply_failure';
  static const String autoUpdateNotificationsPreferenceEnabledCounter = 'auto_update_notifications_preference_enabled';
  static const String autoUpdateNotificationsPreferenceDisabledCounter =
      'auto_update_notifications_preference_disabled';
  static const String autoUpdateAutomaticSilentPreferenceEnabledCounter =
      'auto_update_automatic_silent_preference_enabled';
  static const String autoUpdateAutomaticSilentPreferenceDisabledCounter =
      'auto_update_automatic_silent_preference_disabled';
  static const String autoUpdateManualOnlyModeAppliedCounter = 'auto_update_manual_only_mode_applied';
}
