part of 'metrics_collector.dart';

/// ODBC pool, connection, batch, and query execution metrics.
base mixin MetricsCollectorOdbcDomain on MetricsCollectorCore {
  int get timeoutCancelSuccessCount => store.counterValue(MetricsCounterNames.timeoutCancelSuccessCounter);
  int get timeoutCancelFailureCount => store.counterValue(MetricsCounterNames.timeoutCancelFailureCounter);
  int get transactionRollbackFailureCount => store.counterValue(MetricsCounterNames.transactionRollbackFailureCounter);
  int get transactionRollbackAttemptCount => store.counterValue(MetricsCounterNames.transactionRollbackAttemptCounter);
  int get multiResultPoolVacuousFallbackCount =>
      store.counterValue(MetricsCounterNames.multiResultPoolVacuousFallbackCounter);
  int get multiResultDirectStillVacuousCount =>
      store.counterValue(MetricsCounterNames.multiResultDirectStillVacuousCounter);
  int get transactionalBatchDirectPathCount => store.counterValue(MetricsCounterNames.transactionalBatchDirectPathCounter);
  int get transactionalBatchNativePoolPathCount =>
      store.counterValue(MetricsCounterNames.transactionalBatchNativePoolPathCounter);
  int get transactionalBatchNativePoolFallbackCount =>
      store.counterValue(MetricsCounterNames.transactionalBatchNativePoolFallbackCounter);
  int get batchBulkInsertRecommendedCount => store.counterValue(MetricsCounterNames.batchBulkInsertRecommendedCounter);
  int get batchBulkInsertRoutedCount => store.counterValue(MetricsCounterNames.batchBulkInsertRoutedCounter);
  int get directConnectionFallbackCount => store.counterValue(MetricsCounterNames.directConnectionFallbackCounter);
  int get odbcNativePoolFallbackCount => store.counterValue(MetricsCounterNames.odbcNativePoolFallbackCounter);
  int get odbcNativePoolOptionsSkipCount => store.counterValue(MetricsCounterNames.odbcNativePoolOptionsSkipCounter);
  int get odbcNativeCompatibleAcquireAttemptCount =>
      store.counterValue(MetricsCounterNames.odbcNativeCompatibleAcquireAttemptCounter);
  int get odbcNativeCompatibleAcquireSuccessCount =>
      store.counterValue(MetricsCounterNames.odbcNativeCompatibleAcquireSuccessCounter);
  int get readOnlyBatchParallelCount => store.counterValue(MetricsCounterNames.readOnlyBatchParallelCounter);
  int get readOnlyBatchParallelCappedCount => store.counterValue(MetricsCounterNames.readOnlyBatchParallelCappedCounter);
  int get readOnlyBatchNativePoolPathCount => store.counterValue(MetricsCounterNames.readOnlyBatchNativePoolPathCounter);
  int get readOnlyBatchNativePoolFallbackCount =>
      store.counterValue(MetricsCounterNames.readOnlyBatchNativePoolFallbackCounter);
  int get directConnectionAcquireTimeoutCount =>
      store.counterValue(MetricsCounterNames.directConnectionAcquireTimeoutCounter);
  int get activeDirectConnections => store.activeDirectConnections;
  int get maxActiveDirectConnections => store.maxActiveDirectConnections;
  int get poolReleaseFailureCount => store.counterValue(MetricsCounterNames.poolReleaseFailureCounter);
  int get poolDiscardInflightCount => store.poolDiscardInflight;
  int get bulkInsertChunkedCount => store.counterValue(MetricsCounterNames.bulkInsertChunkedCounter);
  int get bulkInsertParallelCount => store.counterValue(MetricsCounterNames.bulkInsertParallelCounter);
  int get poolRecycleCount => store.counterValue(MetricsCounterNames.poolRecycleCounter);
  int get poolRecycleFailureCount => store.counterValue(MetricsCounterNames.poolRecycleFailureCounter);
  int get poolAcquireTimeoutCount => store.counterValue(MetricsCounterNames.poolAcquireTimeoutCounter);
  int get connectTimeoutCount => store.counterValue(MetricsCounterNames.connectTimeoutCounter);
  int get queryTimeoutCount => store.counterValue(MetricsCounterNames.queryTimeoutCounter);
  int get preparedStatementReuseCount => store.counterValue(MetricsCounterNames.preparedStatementReuseCounter);
  int get preparedStatementCacheHitCount => store.counterValue(MetricsCounterNames.preparedStatementCacheHitCounter);
  int get preparedStatementCacheMissCount => store.counterValue(MetricsCounterNames.preparedStatementCacheMissCounter);
  int get streamingBatchedPathCount => store.counterValue(MetricsCounterNames.streamingBatchedPathCounter);
  int get streamingSingleChunkPathCount => store.counterValue(MetricsCounterNames.streamingSingleChunkPathCounter);
  int get streamCancelRequestCount => store.counterValue(MetricsCounterNames.streamCancelRequestCounter);
  int get streamCancelBackpressureCount => store.counterValue(MetricsCounterNames.streamCancelBackpressureCounter);
  int get streamCancelDisconnectFailureCount =>
      store.counterValue(MetricsCounterNames.streamCancelDisconnectFailureCounter);
  int get streamCancelDisconnectTimeoutCount =>
      store.counterValue(MetricsCounterNames.streamCancelDisconnectTimeoutCounter);

  void recordPoolWaitTime(Duration waitTime) => _recordDurationSample(store.poolWaitTimes, waitTime);

  void recordDirectConnectionWaitTime(Duration waitTime) =>
      _recordDurationSample(store.directConnectionWaitTimes, waitTime);

  void recordReadOnlyBatchParallelWaitTime(Duration waitTime) =>
      _recordDurationSample(store.readOnlyBatchParallelWaitTimes, waitTime);

  void recordConnectTime(Duration connectTime) => _recordDurationSample(store.connectTimes, connectTime);

  void recordSqlExecutionTime(
    Duration executionTime, {
    String mode = 'unknown',
  }) {
    _recordDurationSample(store.sqlExecutionTimes, executionTime);
    final samples = store.sqlExecutionTimesByMode.putIfAbsent(mode, ListQueue<Duration>.new);
    _recordDurationSample(samples, executionTime);
    final timestamps = store.sqlExecutionTimestampsByMode.putIfAbsent(mode, ListQueue<DateTime>.new);
    _recordTimestampSample(timestamps, DateTime.now());
  }

  void recordPreparedPrepareTime(Duration prepareTime) => _recordDurationSample(store.preparedPrepareTimes, prepareTime);

  void recordStreamingBatchedPath() => _incrementEventCounter(MetricsCounterNames.streamingBatchedPathCounter);

  void recordStreamingSingleChunkPath() => _incrementEventCounter(MetricsCounterNames.streamingSingleChunkPathCounter);

  void recordTimeoutCancelSuccess() => _incrementEventCounter(MetricsCounterNames.timeoutCancelSuccessCounter);

  void recordTimeoutCancelFailure() => _incrementEventCounter(MetricsCounterNames.timeoutCancelFailureCounter);

  void recordTransactionRollbackAttempt() =>
      _incrementEventCounter(MetricsCounterNames.transactionRollbackAttemptCounter);

  void recordTransactionRollbackFailure() =>
      _incrementEventCounter(MetricsCounterNames.transactionRollbackFailureCounter);

  void recordMultiResultPoolVacuousFallback() =>
      _incrementEventCounter(MetricsCounterNames.multiResultPoolVacuousFallbackCounter);

  void recordMultiResultDirectStillVacuous() =>
      _incrementEventCounter(MetricsCounterNames.multiResultDirectStillVacuousCounter);

  void recordTransactionalBatchDirectPath() =>
      _incrementEventCounter(MetricsCounterNames.transactionalBatchDirectPathCounter);

  void recordTransactionalBatchNativePoolPath() =>
      _incrementEventCounter(MetricsCounterNames.transactionalBatchNativePoolPathCounter);

  void recordTransactionalBatchNativePoolFallback() =>
      _incrementEventCounter(MetricsCounterNames.transactionalBatchNativePoolFallbackCounter);

  void recordBatchBulkInsertRecommended() {
    _incrementEventCounter(MetricsCounterNames.batchBulkInsertRecommendedCounter);
    recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.batchBulkInsertRecommendedReason,
    );
  }

  void recordBatchBulkInsertRouted() {
    _incrementEventCounter(MetricsCounterNames.batchBulkInsertRoutedCounter);
    recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.batchBulkInsertRoutedReason,
    );
  }

  void recordDirectConnectionFallback() => _incrementEventCounter(MetricsCounterNames.directConnectionFallbackCounter);

  void recordOdbcNativePoolFallback() => _incrementEventCounter(MetricsCounterNames.odbcNativePoolFallbackCounter);

  void recordOdbcNativeFallback(String reason) {
    final normalizedReason = reason.trim().isEmpty ? 'unknown' : reason.trim();
    _incrementEventCounter(MetricsCounterNames.odbcNativeFallbackTotalCounter);
    store.odbcNativeFallbackReasons[normalizedReason] =
        (store.odbcNativeFallbackReasons[normalizedReason] ?? 0) + 1;
    recordDiagnosticReason(
      category: 'odbc_native_fallback',
      reason: normalizedReason,
    );
  }

  void recordOdbcNativeCircuitOpened() {
    _incrementEventCounter(MetricsCounterNames.odbcNativeCircuitOpenedCounter);
    recordDiagnosticReason(
      category: 'odbc_native',
      reason: 'native_circuit_open',
    );
  }

  void recordOdbcBufferExpansion() => _incrementEventCounter(MetricsCounterNames.odbcBufferExpansionCounter);

  void recordOdbcInvalidConnectionRecycle() =>
      _incrementEventCounter(MetricsCounterNames.odbcInvalidConnectionRecycleCounter);

  void recordOdbcNativePoolOptionsSkip() => _incrementEventCounter(MetricsCounterNames.odbcNativePoolOptionsSkipCounter);

  void recordOdbcNativeCompatibleAcquireAttempt() =>
      _incrementEventCounter(MetricsCounterNames.odbcNativeCompatibleAcquireAttemptCounter);

  void recordOdbcNativeCompatibleAcquireSuccess() =>
      _incrementEventCounter(MetricsCounterNames.odbcNativeCompatibleAcquireSuccessCounter);

  void recordReadOnlyBatchNativePoolPath() =>
      _incrementEventCounter(MetricsCounterNames.readOnlyBatchNativePoolPathCounter);

  void recordReadOnlyBatchNativePoolFallback() =>
      _incrementEventCounter(MetricsCounterNames.readOnlyBatchNativePoolFallbackCounter);

  void recordReadOnlyBatchParallel({
    int? requestedParallelism,
    int? effectiveParallelism,
  }) {
    _incrementEventCounter(MetricsCounterNames.readOnlyBatchParallelCounter);
    if (requestedParallelism != null) {
      store.readOnlyBatchParallelLastRequested = requestedParallelism;
    }
    if (effectiveParallelism != null) {
      store.readOnlyBatchParallelLastEffective = effectiveParallelism;
    }
    if (requestedParallelism != null && effectiveParallelism != null && effectiveParallelism < requestedParallelism) {
      _incrementEventCounter(MetricsCounterNames.readOnlyBatchParallelCappedCounter);
      recordDiagnosticReason(
        category: 'batch',
        reason: RpcSqlDiagnosticsConstants.readOnlyParallelCappedReason,
      );
    }
  }

  void recordDirectConnectionAcquireTimeout() =>
      _incrementEventCounter(MetricsCounterNames.directConnectionAcquireTimeoutCounter);

  void recordDirectConnectionOpened() {
    store.activeDirectConnections++;
    if (store.activeDirectConnections > store.maxActiveDirectConnections) {
      store.maxActiveDirectConnections = store.activeDirectConnections;
    }
    _incrementEventCounter('direct_connection_opened');
  }

  void recordDirectConnectionClosed() {
    if (store.activeDirectConnections > 0) {
      store.activeDirectConnections--;
    }
    _incrementEventCounter('direct_connection_closed');
  }

  void recordPoolReleaseFailure() => _incrementEventCounter(MetricsCounterNames.poolReleaseFailureCounter);

  void recordPoolDiscardInflightStarted() {
    store.poolDiscardInflight++;
    store.eventCounters[MetricsCounterNames.poolDiscardInflightCounter] = store.poolDiscardInflight;
  }

  void recordPoolDiscardInflightCompleted() {
    if (store.poolDiscardInflight > 0) {
      store.poolDiscardInflight--;
    }
    store.eventCounters[MetricsCounterNames.poolDiscardInflightCounter] = store.poolDiscardInflight;
  }

  void recordPoolDiscardReconciliationStale() =>
      _incrementEventCounter(MetricsCounterNames.poolDiscardReconciliationStaleCounter);

  void recordPoolDiscardReconciliationRemediated() =>
      _incrementEventCounter(MetricsCounterNames.poolDiscardReconciliationRemediatedCounter);

  void recordPoolDiscardReconciliationForceRelease() =>
      _incrementEventCounter(MetricsCounterNames.poolDiscardReconciliationForceReleaseCounter);

  void recordBulkInsertChunked() => _incrementEventCounter(MetricsCounterNames.bulkInsertChunkedCounter);

  void recordBulkInsertParallel() => _incrementEventCounter(MetricsCounterNames.bulkInsertParallelCounter);

  void recordPoolRecycle() => _incrementEventCounter(MetricsCounterNames.poolRecycleCounter);

  void recordPoolRecycleFailure() => _incrementEventCounter(MetricsCounterNames.poolRecycleFailureCounter);

  void recordOdbcEventConnectionLost() => _incrementEventCounter(MetricsCounterNames.odbcEventConnectionLostCounter);

  void recordOdbcEventAutoReconnectAttempted() =>
      _incrementEventCounter(MetricsCounterNames.odbcEventAutoReconnectAttemptedCounter);

  void recordOdbcEventWorkerRecovered() => _incrementEventCounter(MetricsCounterNames.odbcEventWorkerRecoveredCounter);

  void recordOdbcEventPoolResize() => _incrementEventCounter(MetricsCounterNames.odbcEventPoolResizeCounter);

  void recordOdbcEventSlowQueryDetected() => _incrementEventCounter(MetricsCounterNames.odbcEventSlowQueryDetectedCounter);

  void recordTransactionalBatchReadOnlyInference() =>
      _incrementEventCounter(MetricsCounterNames.transactionalBatchReadOnlyInferenceCounter);

  void recordTransactionalBatchDeadlineNearStall() =>
      _incrementEventCounter(MetricsCounterNames.transactionalBatchDeadlineNearStallCounter);

  void recordPoolAcquireTimeout() => _incrementEventCounter(MetricsCounterNames.poolAcquireTimeoutCounter);

  void recordConnectTimeout() => _incrementEventCounter(MetricsCounterNames.connectTimeoutCounter);

  void recordQueryTimeout() => _incrementEventCounter(MetricsCounterNames.queryTimeoutCounter);

  void recordOdbcQueryTimeoutByStage(String stage) {
    final normalizedStage = stage.trim().isEmpty ? 'unknown' : stage.trim();
    store.odbcQueryTimeoutByStage[normalizedStage] = (store.odbcQueryTimeoutByStage[normalizedStage] ?? 0) + 1;
  }

  void recordPreparedStatementReuse() {
    _incrementEventCounter(MetricsCounterNames.preparedStatementReuseCounter);
    _incrementEventCounter(MetricsCounterNames.preparedStatementCacheHitCounter);
  }

  void recordPreparedStatementCacheMiss() => _incrementEventCounter(MetricsCounterNames.preparedStatementCacheMissCounter);

  void recordStreamCancelRequest() => _incrementEventCounter(MetricsCounterNames.streamCancelRequestCounter);

  void recordStreamCancelBackpressure() => _incrementEventCounter(MetricsCounterNames.streamCancelBackpressureCounter);

  void recordStreamCancelDisconnectFailure() =>
      _incrementEventCounter(MetricsCounterNames.streamCancelDisconnectFailureCounter);

  void recordStreamCancelDisconnectTimeout() =>
      _incrementEventCounter(MetricsCounterNames.streamCancelDisconnectTimeoutCounter);
}
