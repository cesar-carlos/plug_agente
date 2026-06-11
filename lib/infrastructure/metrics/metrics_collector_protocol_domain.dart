part of 'metrics_collector.dart';

/// RPC, streaming, schema validation, and idempotency metrics.
base mixin MetricsCollectorProtocolDomain on MetricsCollectorCore {
  int get idempotencyFingerprintMismatchCount => _eventCounters[MetricsCollectorCore.idempotencyFingerprintMismatchCounter] ?? 0;
  int get rpcSqlExecuteStreamingChunksResponseCount =>
      _eventCounters[MetricsCollectorCore.rpcSqlExecuteStreamingChunksResponseCounter] ?? 0;
  int get rpcSqlExecuteStreamingFromDbResponseCount =>
      _eventCounters[MetricsCollectorCore.rpcSqlExecuteStreamingFromDbResponseCounter] ?? 0;
  int get rpcSqlExecuteAutoStreamingFromDbResponseCount =>
      _eventCounters[MetricsCollectorCore.rpcSqlExecuteAutoStreamingFromDbResponseCounter] ?? 0;
  int get rpcSqlExecuteAllowlistDbStreamingResponseCount =>
      _eventCounters[MetricsCollectorCore.rpcSqlExecuteAllowlistDbStreamingResponseCounter] ?? 0;
  int get rpcSqlExecuteMaterializedResponseCount => _eventCounters[MetricsCollectorCore.rpcSqlExecuteMaterializedResponseCounter] ?? 0;
  int get rpcStreamTerminalCompleteEmittedCount => _eventCounters[MetricsCollectorCore.rpcStreamTerminalCompleteEmittedCounter] ?? 0;
  int get rpcStreamTerminalCompleteFailedCount => _eventCounters[MetricsCollectorCore.rpcStreamTerminalCompleteFailedCounter] ?? 0;
  int get rpcResponseAckRetryCount => _eventCounters[MetricsCollectorCore.rpcResponseAckRetryCounter] ?? 0;
  int get rpcResponseAckDeliveredCount => _eventCounters[MetricsCollectorCore.rpcResponseAckDeliveredCounter] ?? 0;
  int get rpcResponseAckAbortedConnectionChangeCount =>
      _eventCounters[MetricsCollectorCore.rpcResponseAckAbortedConnectionChangeCounter] ?? 0;
  int get rpcResponseAckFallbackWithoutAckCount => _eventCounters[MetricsCollectorCore.rpcResponseAckFallbackWithoutAckCounter] ?? 0;
  int get rpcResponseAckSkippedSqlExecuteCount => _eventCounters[MetricsCollectorCore.rpcResponseAckSkippedSqlExecuteCounter] ?? 0;
  int get rpcResponseAckSkippedSqlExecuteBatchCount =>
      _eventCounters[MetricsCollectorCore.rpcResponseAckSkippedSqlExecuteBatchCounter] ?? 0;

  void recordIdempotencyFingerprintMismatch() => _incrementEventCounter(MetricsCollectorCore.idempotencyFingerprintMismatchCounter);

  void recordRpcSqlExecuteStreamingChunksResponse() =>
      _incrementEventCounter(MetricsCollectorCore.rpcSqlExecuteStreamingChunksResponseCounter);

  void recordRpcSqlExecuteStreamingFromDbResponse() =>
      _incrementEventCounter(MetricsCollectorCore.rpcSqlExecuteStreamingFromDbResponseCounter);

  void recordRpcSqlExecuteAutoStreamingFromDbResponse() {
    _incrementEventCounter(MetricsCollectorCore.rpcSqlExecuteAutoStreamingFromDbResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.autoDbStreamingReason,
    );
  }

  void recordRpcSqlExecutePreferDbStreamingResponse() {
    _incrementEventCounter(MetricsCollectorCore.rpcSqlExecutePreferDbStreamingResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.preferDbStreamingReason,
    );
  }

  void recordRpcSqlExecuteAllowlistDbStreamingResponse() {
    _incrementEventCounter(MetricsCollectorCore.rpcSqlExecuteAllowlistDbStreamingResponseCounter);
    recordDiagnosticReason(
      category: 'streaming',
      reason: RpcSqlDiagnosticsConstants.allowlistDbStreamingReason,
    );
  }

  void recordRpcSqlExecuteDbStreamingSkipped(String reason) {
    _incrementEventCounter(MetricsCollectorCore.rpcSqlExecuteDbStreamingSkipCounter);
    _streamingSkipReasons[reason] = (_streamingSkipReasons[reason] ?? 0) + 1;
    recordDiagnosticReason(
      category: 'streaming_skip',
      reason: reason,
    );
  }

  void recordRpcSqlExecuteMaterializedResponse() => _incrementEventCounter(MetricsCollectorCore.rpcSqlExecuteMaterializedResponseCounter);

  void recordRpcStreamTerminalCompleteEmitted() => _incrementEventCounter(MetricsCollectorCore.rpcStreamTerminalCompleteEmittedCounter);

  void recordRpcStreamTerminalCompleteFailed() => _incrementEventCounter(MetricsCollectorCore.rpcStreamTerminalCompleteFailedCounter);

  void recordRpcResponseAckRetry() => _incrementEventCounter(MetricsCollectorCore.rpcResponseAckRetryCounter);

  void recordRpcResponseAckDelivered() => _incrementEventCounter(MetricsCollectorCore.rpcResponseAckDeliveredCounter);

  void recordRpcResponseAckAbortedConnectionChange() =>
      _incrementEventCounter(MetricsCollectorCore.rpcResponseAckAbortedConnectionChangeCounter);

  void recordRpcResponseAckFallbackWithoutAck() => _incrementEventCounter(MetricsCollectorCore.rpcResponseAckFallbackWithoutAckCounter);

  void recordRpcResponseAckSkippedSqlExecute() => _incrementEventCounter(MetricsCollectorCore.rpcResponseAckSkippedSqlExecuteCounter);

  void recordRpcResponseAckSkippedSqlExecuteBatch() =>
      _incrementEventCounter(MetricsCollectorCore.rpcResponseAckSkippedSqlExecuteBatchCounter);

  void recordRpcAgentActionRemoteOutcome(String rpcMethod, {required bool success}) {
    if (!AgentActionRpcConstants.remotePublishedRpcMethodNames.contains(rpcMethod)) {
      return;
    }
    final counter = switch ((rpcMethod, success)) {
      (AgentActionRpcConstants.agentActionRunRpcMethodName, true) => MetricsCollectorCore.rpcRemoteAgentActionRunSuccessCounter,
      (AgentActionRpcConstants.agentActionRunRpcMethodName, false) => MetricsCollectorCore.rpcRemoteAgentActionRunErrorCounter,
      (AgentActionRpcConstants.agentActionValidateRunRpcMethodName, true) =>
        MetricsCollectorCore.rpcRemoteAgentActionValidateRunSuccessCounter,
      (AgentActionRpcConstants.agentActionValidateRunRpcMethodName, false) =>
        MetricsCollectorCore.rpcRemoteAgentActionValidateRunErrorCounter,
      (AgentActionRpcConstants.agentActionCancelRpcMethodName, true) => MetricsCollectorCore.rpcRemoteAgentActionCancelSuccessCounter,
      (AgentActionRpcConstants.agentActionCancelRpcMethodName, false) => MetricsCollectorCore.rpcRemoteAgentActionCancelErrorCounter,
      (AgentActionRpcConstants.agentActionGetExecutionRpcMethodName, true) =>
        MetricsCollectorCore.rpcRemoteAgentActionGetExecutionSuccessCounter,
      (AgentActionRpcConstants.agentActionGetExecutionRpcMethodName, false) =>
        MetricsCollectorCore.rpcRemoteAgentActionGetExecutionErrorCounter,
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
      AgentActionRpcConstants.agentActionRunRpcMethodName => MetricsCollectorCore.rpcRemoteAgentActionRunNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionValidateRunRpcMethodName =>
        MetricsCollectorCore.rpcRemoteAgentActionValidateRunNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionCancelRpcMethodName => MetricsCollectorCore.rpcRemoteAgentActionCancelNotificationRejectedCounter,
      AgentActionRpcConstants.agentActionGetExecutionRpcMethodName =>
        MetricsCollectorCore.rpcRemoteAgentActionGetExecutionNotificationRejectedCounter,
      _ => null,
    };
    if (counter != null) {
      _incrementEventCounter(counter);
    }
  }

  void recordRpcAgentActionBatchReadLimitRejected() {
    _incrementEventCounter(MetricsCollectorCore.rpcRemoteAgentActionBatchReadLimitRejectedCounter);
  }

  void recordRpcMethodConcurrencyLimited(String rpcMethod) {
    _incrementEventCounter(MetricsCollectorCore.rpcMethodConcurrencyLimitedCounter);
    recordDiagnosticReason(
      category: 'rpc_method_concurrency_limit',
      reason: rpcMethod,
    );
  }

  void recordSqlStreamCancelled(String reason) {
    _incrementEventCounter(MetricsCollectorCore.rpcSqlStreamCancelledCounter);
    recordDiagnosticReason(
      category: 'sql_stream_cancelled',
      reason: reason,
    );
  }

  void recordSqlStreamCancelFailed(String reason) {
    _incrementEventCounter(MetricsCollectorCore.rpcSqlStreamCancelFailedCounter);
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
    _incrementEventCounter(success ? MetricsCollectorCore.schemaValidationSuccessCounter : MetricsCollectorCore.schemaValidationFailureCounter);
    final key = '${direction.trim()}:${schemaId.trim()}';
    final elapsedUs = elapsed.inMicroseconds;
    _schemaValidationDurationUs += elapsedUs;
    _schemaValidationDurationUsByKey[key] = (_schemaValidationDurationUsByKey[key] ?? 0) + elapsedUs;
    _schemaValidationCountByKey[key] = (_schemaValidationCountByKey[key] ?? 0) + 1;
    if (!success) {
      _schemaValidationFailuresByKey[key] = (_schemaValidationFailuresByKey[key] ?? 0) + 1;
    }
  }

  void recordSchemaValidationSkippedLargePayload({
    required String direction,
  }) {
    _incrementEventCounter(MetricsCollectorCore.schemaValidationSkippedLargePayloadCounter);
    recordDiagnosticReason(
      category: 'schema_validation_skip',
      reason: '${direction.trim()}:large_payload',
    );
  }
}
