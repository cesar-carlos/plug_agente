part of 'metrics_collector.dart';

/// RPC, streaming, schema validation, and idempotency metrics.
base mixin MetricsCollectorProtocolDomain on MetricsCollectorCore {
  int get idempotencyFingerprintMismatchCount =>
      store.counterValue(MetricsCounterNames.idempotencyFingerprintMismatchCounter);
  int get rpcSqlExecuteStreamingChunksResponseCount =>
      store.counterValue(MetricsCounterNames.rpcSqlExecuteStreamingChunksResponseCounter);
  int get rpcSqlExecuteStreamingFromDbResponseCount =>
      store.counterValue(MetricsCounterNames.rpcSqlExecuteStreamingFromDbResponseCounter);
  int get rpcSqlExecuteAutoStreamingFromDbResponseCount =>
      store.counterValue(MetricsCounterNames.rpcSqlExecuteAutoStreamingFromDbResponseCounter);
  int get rpcSqlExecuteAllowlistDbStreamingResponseCount =>
      store.counterValue(MetricsCounterNames.rpcSqlExecuteAllowlistDbStreamingResponseCounter);
  int get rpcSqlExecuteMaterializedResponseCount =>
      store.counterValue(MetricsCounterNames.rpcSqlExecuteMaterializedResponseCounter);
  int get rpcStreamTerminalCompleteEmittedCount =>
      store.counterValue(MetricsCounterNames.rpcStreamTerminalCompleteEmittedCounter);
  int get rpcStreamTerminalCompleteFailedCount =>
      store.counterValue(MetricsCounterNames.rpcStreamTerminalCompleteFailedCounter);
  int get rpcResponseAckRetryCount => store.counterValue(MetricsCounterNames.rpcResponseAckRetryCounter);
  int get rpcResponseAckDeliveredCount => store.counterValue(MetricsCounterNames.rpcResponseAckDeliveredCounter);
  int get rpcResponseAckAbortedConnectionChangeCount =>
      store.counterValue(MetricsCounterNames.rpcResponseAckAbortedConnectionChangeCounter);
  int get rpcResponseAckFallbackWithoutAckCount =>
      store.counterValue(MetricsCounterNames.rpcResponseAckFallbackWithoutAckCounter);
  int get rpcResponseAckSkippedSqlExecuteCount =>
      store.counterValue(MetricsCounterNames.rpcResponseAckSkippedSqlExecuteCounter);
  int get rpcResponseAckSkippedSqlExecuteBatchCount =>
      store.counterValue(MetricsCounterNames.rpcResponseAckSkippedSqlExecuteBatchCounter);

  void recordIdempotencyFingerprintMismatch() =>
      _incrementEventCounter(MetricsCounterNames.idempotencyFingerprintMismatchCounter);

  void recordRpcSqlExecuteStreamingChunksResponse() =>
      _incrementEventCounter(MetricsCounterNames.rpcSqlExecuteStreamingChunksResponseCounter);

  void recordRpcSqlExecuteStreamingFromDbResponse() =>
      _incrementEventCounter(MetricsCounterNames.rpcSqlExecuteStreamingFromDbResponseCounter);

  void recordRpcSqlExecuteAutoStreamingFromDbResponse() {
    _incrementEventCounter(MetricsCounterNames.rpcSqlExecuteAutoStreamingFromDbResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.autoDbStreamingReason,
    );
  }

  void recordRpcSqlExecutePreferDbStreamingResponse() {
    _incrementEventCounter(MetricsCounterNames.rpcSqlExecutePreferDbStreamingResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.preferDbStreamingReason,
    );
  }

  void recordRpcSqlExecuteAllowlistDbStreamingResponse() {
    _incrementEventCounter(MetricsCounterNames.rpcSqlExecuteAllowlistDbStreamingResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.allowlistDbStreamingReason,
    );
  }

  void recordRpcSqlExecuteDbStreamingSkipped(String reason) {
    _incrementEventCounter(MetricsCounterNames.rpcSqlExecuteDbStreamingSkipCounter);
    store.streamingSkipReasons[reason] = (store.streamingSkipReasons[reason] ?? 0) + 1;
    recordDiagnosticReason(
      category: 'streaming_skip',
      reason: reason,
    );
  }

  void recordRpcSqlExecuteMaterializedResponse() =>
      _incrementEventCounter(MetricsCounterNames.rpcSqlExecuteMaterializedResponseCounter);

  void recordRpcStreamTerminalCompleteEmitted() =>
      _incrementEventCounter(MetricsCounterNames.rpcStreamTerminalCompleteEmittedCounter);

  void recordRpcStreamTerminalCompleteFailed() =>
      _incrementEventCounter(MetricsCounterNames.rpcStreamTerminalCompleteFailedCounter);

  void recordRpcResponseAckRetry() => _incrementEventCounter(MetricsCounterNames.rpcResponseAckRetryCounter);

  void recordRpcResponseAckDelivered() => _incrementEventCounter(MetricsCounterNames.rpcResponseAckDeliveredCounter);

  void recordRpcResponseAckAbortedConnectionChange() =>
      _incrementEventCounter(MetricsCounterNames.rpcResponseAckAbortedConnectionChangeCounter);

  void recordRpcResponseAckFallbackWithoutAck() =>
      _incrementEventCounter(MetricsCounterNames.rpcResponseAckFallbackWithoutAckCounter);

  void recordRpcResponseAckSkippedSqlExecute() =>
      _incrementEventCounter(MetricsCounterNames.rpcResponseAckSkippedSqlExecuteCounter);

  void recordRpcResponseAckSkippedSqlExecuteBatch() =>
      _incrementEventCounter(MetricsCounterNames.rpcResponseAckSkippedSqlExecuteBatchCounter);

  void recordRpcAgentActionRemoteOutcome(String rpcMethod, {required bool success}) {
    if (!AgentActionRpcConstants.remotePublishedRpcMethodNames.contains(rpcMethod)) {
      return;
    }
    final counter = switch ((rpcMethod, success)) {
      (AgentActionRpcConstants.agentActionRunRpcMethodName, true) =>
        MetricsCounterNames.rpcRemoteAgentActionRunSuccessCounter,
      (AgentActionRpcConstants.agentActionRunRpcMethodName, false) =>
        MetricsCounterNames.rpcRemoteAgentActionRunErrorCounter,
      (AgentActionRpcConstants.agentActionValidateRunRpcMethodName, true) =>
        MetricsCounterNames.rpcRemoteAgentActionValidateRunSuccessCounter,
      (AgentActionRpcConstants.agentActionValidateRunRpcMethodName, false) =>
        MetricsCounterNames.rpcRemoteAgentActionValidateRunErrorCounter,
      (AgentActionRpcConstants.agentActionCancelRpcMethodName, true) =>
        MetricsCounterNames.rpcRemoteAgentActionCancelSuccessCounter,
      (AgentActionRpcConstants.agentActionCancelRpcMethodName, false) =>
        MetricsCounterNames.rpcRemoteAgentActionCancelErrorCounter,
      (AgentActionRpcConstants.agentActionGetExecutionRpcMethodName, true) =>
        MetricsCounterNames.rpcRemoteAgentActionGetExecutionSuccessCounter,
      (AgentActionRpcConstants.agentActionGetExecutionRpcMethodName, false) =>
        MetricsCounterNames.rpcRemoteAgentActionGetExecutionErrorCounter,
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
      AgentActionRpcConstants.agentActionRunRpcMethodName =>
        MetricsCounterNames.rpcRemoteAgentActionRunNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionValidateRunRpcMethodName =>
        MetricsCounterNames.rpcRemoteAgentActionValidateRunNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionCancelRpcMethodName =>
        MetricsCounterNames.rpcRemoteAgentActionCancelNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionGetExecutionRpcMethodName =>
        MetricsCounterNames.rpcRemoteAgentActionGetExecutionNotificationRejectedCounter,
      _ => null,
    };
    if (counter != null) {
      _incrementEventCounter(counter);
    }
  }

  void recordRpcAgentActionBatchReadLimitRejected() {
    _incrementEventCounter(MetricsCounterNames.rpcRemoteAgentActionBatchReadLimitRejectedCounter);
  }

  void recordRpcMethodConcurrencyLimited(String rpcMethod) {
    _incrementEventCounter(MetricsCounterNames.rpcMethodConcurrencyLimitedCounter);
    recordDiagnosticReason(
      category: 'rpc_method_concurrency_limit',
      reason: rpcMethod,
    );
  }

  void recordSqlStreamCancelled(String reason) {
    _incrementEventCounter(MetricsCounterNames.rpcSqlStreamCancelledCounter);
    recordDiagnosticReason(
      category: 'sql_stream_cancelled',
      reason: reason,
    );
  }

  void recordSqlStreamCancelFailed(String reason) {
    _incrementEventCounter(MetricsCounterNames.rpcSqlStreamCancelFailedCounter);
    recordDiagnosticReason(
      category: 'sql_stream_cancel_failed',
      reason: reason,
    );
  }

  void recordSchemaValidation({
    required String direction,
    required String schemaId,
    required bool success,
    required Duration elapsed,
  }) {
    _incrementEventCounter(
      success ? MetricsCounterNames.schemaValidationSuccessCounter : MetricsCounterNames.schemaValidationFailureCounter,
    );
    final key = '${direction.trim()}:${schemaId.trim()}';
    final elapsedUs = elapsed.inMicroseconds;
    store.schemaValidationDurationUs += elapsedUs;
    store.schemaValidationDurationUsByKey[key] = (store.schemaValidationDurationUsByKey[key] ?? 0) + elapsedUs;
    store.schemaValidationCountByKey[key] = (store.schemaValidationCountByKey[key] ?? 0) + 1;
    if (!success) {
      store.schemaValidationFailuresByKey[key] = (store.schemaValidationFailuresByKey[key] ?? 0) + 1;
    }
  }

  void recordSchemaValidationSkippedLargePayload({
    required String direction,
  }) {
    _incrementEventCounter(MetricsCounterNames.schemaValidationSkippedLargePayloadCounter);
    recordDiagnosticReason(
      category: 'schema_validation_skip',
      reason: '${direction.trim()}:large_payload',
    );
  }
}
