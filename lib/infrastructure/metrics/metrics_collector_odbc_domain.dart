part of 'metrics_collector.dart';

/// ODBC pool, connection, batch, and query execution metrics.
base mixin MetricsCollectorOdbcDomain on MetricsCollectorCore {
  int get timeoutCancelSuccessCount => _eventCounters[MetricsCollectorCore.timeoutCancelSuccessCounter] ?? 0;
  int get timeoutCancelFailureCount => _eventCounters[MetricsCollectorCore.timeoutCancelFailureCounter] ?? 0;
  int get transactionRollbackFailureCount => _eventCounters[MetricsCollectorCore.transactionRollbackFailureCounter] ?? 0;
  int get transactionRollbackAttemptCount => _eventCounters[MetricsCollectorCore.transactionRollbackAttemptCounter] ?? 0;
  int get multiResultPoolVacuousFallbackCount => _eventCounters[MetricsCollectorCore.multiResultPoolVacuousFallbackCounter] ?? 0;
  int get multiResultDirectStillVacuousCount => _eventCounters[MetricsCollectorCore.multiResultDirectStillVacuousCounter] ?? 0;
  int get transactionalBatchDirectPathCount => _eventCounters[MetricsCollectorCore.transactionalBatchDirectPathCounter] ?? 0;
  int get transactionalBatchNativePoolPathCount => _eventCounters[MetricsCollectorCore.transactionalBatchNativePoolPathCounter] ?? 0;
  int get transactionalBatchNativePoolFallbackCount =>
      _eventCounters[MetricsCollectorCore.transactionalBatchNativePoolFallbackCounter] ?? 0;
  int get batchBulkInsertRecommendedCount => _eventCounters[MetricsCollectorCore.batchBulkInsertRecommendedCounter] ?? 0;
  int get batchBulkInsertRoutedCount => _eventCounters[MetricsCollectorCore.batchBulkInsertRoutedCounter] ?? 0;
  int get directConnectionFallbackCount => _eventCounters[MetricsCollectorCore.directConnectionFallbackCounter] ?? 0;
  int get odbcNativePoolFallbackCount => _eventCounters[MetricsCollectorCore.odbcNativePoolFallbackCounter] ?? 0;
  int get odbcNativePoolOptionsSkipCount => _eventCounters[MetricsCollectorCore.odbcNativePoolOptionsSkipCounter] ?? 0;
  int get odbcNativeCompatibleAcquireAttemptCount => _eventCounters[MetricsCollectorCore.odbcNativeCompatibleAcquireAttemptCounter] ?? 0;
  int get odbcNativeCompatibleAcquireSuccessCount => _eventCounters[MetricsCollectorCore.odbcNativeCompatibleAcquireSuccessCounter] ?? 0;
  int get readOnlyBatchParallelCount => _eventCounters[MetricsCollectorCore.readOnlyBatchParallelCounter] ?? 0;
  int get readOnlyBatchParallelCappedCount => _eventCounters[MetricsCollectorCore.readOnlyBatchParallelCappedCounter] ?? 0;
  int get readOnlyBatchNativePoolPathCount => _eventCounters[MetricsCollectorCore.readOnlyBatchNativePoolPathCounter] ?? 0;
  int get readOnlyBatchNativePoolFallbackCount => _eventCounters[MetricsCollectorCore.readOnlyBatchNativePoolFallbackCounter] ?? 0;
  int get directConnectionAcquireTimeoutCount => _eventCounters[MetricsCollectorCore.directConnectionAcquireTimeoutCounter] ?? 0;
  int get activeDirectConnections => _activeDirectConnections;
  int get maxActiveDirectConnections => _maxActiveDirectConnections;
  int get poolReleaseFailureCount => _eventCounters[MetricsCollectorCore.poolReleaseFailureCounter] ?? 0;
  int get poolDiscardInflightCount => _poolDiscardInflight;
  int get bulkInsertChunkedCount => _eventCounters[MetricsCollectorCore.bulkInsertChunkedCounter] ?? 0;
  int get bulkInsertParallelCount => _eventCounters[MetricsCollectorCore.bulkInsertParallelCounter] ?? 0;
  int get poolRecycleCount => _eventCounters[MetricsCollectorCore.poolRecycleCounter] ?? 0;
  int get poolRecycleFailureCount => _eventCounters[MetricsCollectorCore.poolRecycleFailureCounter] ?? 0;
  int get poolAcquireTimeoutCount => _eventCounters[MetricsCollectorCore.poolAcquireTimeoutCounter] ?? 0;
  int get connectTimeoutCount => _eventCounters[MetricsCollectorCore.connectTimeoutCounter] ?? 0;
  int get queryTimeoutCount => _eventCounters[MetricsCollectorCore.queryTimeoutCounter] ?? 0;
  int get preparedStatementReuseCount => _eventCounters[MetricsCollectorCore.preparedStatementReuseCounter] ?? 0;
  int get preparedStatementCacheHitCount => _eventCounters[MetricsCollectorCore.preparedStatementCacheHitCounter] ?? 0;
  int get preparedStatementCacheMissCount => _eventCounters[MetricsCollectorCore.preparedStatementCacheMissCounter] ?? 0;
  int get streamingBatchedPathCount => _eventCounters[MetricsCollectorCore.streamingBatchedPathCounter] ?? 0;
  int get streamingSingleChunkPathCount => _eventCounters[MetricsCollectorCore.streamingSingleChunkPathCounter] ?? 0;
  int get streamCancelRequestCount => _eventCounters[MetricsCollectorCore.streamCancelRequestCounter] ?? 0;
  int get streamCancelBackpressureCount => _eventCounters[MetricsCollectorCore.streamCancelBackpressureCounter] ?? 0;
  int get streamCancelDisconnectFailureCount => _eventCounters[MetricsCollectorCore.streamCancelDisconnectFailureCounter] ?? 0;
  int get streamCancelDisconnectTimeoutCount => _eventCounters[MetricsCollectorCore.streamCancelDisconnectTimeoutCounter] ?? 0;

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

  void recordStreamingBatchedPath() => _incrementEventCounter(MetricsCollectorCore.streamingBatchedPathCounter);

  void recordStreamingSingleChunkPath() => _incrementEventCounter(MetricsCollectorCore.streamingSingleChunkPathCounter);

  void recordTimeoutCancelSuccess() => _incrementEventCounter(MetricsCollectorCore.timeoutCancelSuccessCounter);

  void recordTimeoutCancelFailure() => _incrementEventCounter(MetricsCollectorCore.timeoutCancelFailureCounter);

  void recordTransactionRollbackAttempt() => _incrementEventCounter(MetricsCollectorCore.transactionRollbackAttemptCounter);

  void recordTransactionRollbackFailure() => _incrementEventCounter(MetricsCollectorCore.transactionRollbackFailureCounter);

  void recordMultiResultPoolVacuousFallback() => _incrementEventCounter(MetricsCollectorCore.multiResultPoolVacuousFallbackCounter);

  void recordMultiResultDirectStillVacuous() => _incrementEventCounter(MetricsCollectorCore.multiResultDirectStillVacuousCounter);

  void recordTransactionalBatchDirectPath() => _incrementEventCounter(MetricsCollectorCore.transactionalBatchDirectPathCounter);

  void recordTransactionalBatchNativePoolPath() => _incrementEventCounter(MetricsCollectorCore.transactionalBatchNativePoolPathCounter);

  void recordTransactionalBatchNativePoolFallback() =>
      _incrementEventCounter(MetricsCollectorCore.transactionalBatchNativePoolFallbackCounter);

  void recordBatchBulkInsertRecommended() {
    _incrementEventCounter(MetricsCollectorCore.batchBulkInsertRecommendedCounter);
    recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.batchBulkInsertRecommendedReason,
    );
  }

  void recordBatchBulkInsertRouted() {
    _incrementEventCounter(MetricsCollectorCore.batchBulkInsertRoutedCounter);
    recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.batchBulkInsertRoutedReason,
    );
  }

  void recordDirectConnectionFallback() => _incrementEventCounter(MetricsCollectorCore.directConnectionFallbackCounter);

  void recordOdbcNativePoolFallback() => _incrementEventCounter(MetricsCollectorCore.odbcNativePoolFallbackCounter);

  void recordOdbcNativeFallback(String reason) {
    final normalizedReason = reason.trim().isEmpty ? 'unknown' : reason.trim();
    _incrementEventCounter(MetricsCollectorCore.odbcNativeFallbackTotalCounter);
    _odbcNativeFallbackReasons[normalizedReason] = (_odbcNativeFallbackReasons[normalizedReason] ?? 0) + 1;
    recordDiagnosticReason(
      category: 'odbc_native_fallback',
      reason: normalizedReason,
    );
  }

  void recordOdbcNativeCircuitOpened() {
    _incrementEventCounter(MetricsCollectorCore.odbcNativeCircuitOpenedCounter);
    recordDiagnosticReason(
      category: 'odbc_native',
      reason: 'native_circuit_open',
    );
  }

  void recordOdbcBufferExpansion() => _incrementEventCounter(MetricsCollectorCore.odbcBufferExpansionCounter);

  void recordOdbcInvalidConnectionRecycle() => _incrementEventCounter(MetricsCollectorCore.odbcInvalidConnectionRecycleCounter);

  void recordOdbcNativePoolOptionsSkip() => _incrementEventCounter(MetricsCollectorCore.odbcNativePoolOptionsSkipCounter);

  void recordOdbcNativeCompatibleAcquireAttempt() => _incrementEventCounter(MetricsCollectorCore.odbcNativeCompatibleAcquireAttemptCounter);

  void recordOdbcNativeCompatibleAcquireSuccess() => _incrementEventCounter(MetricsCollectorCore.odbcNativeCompatibleAcquireSuccessCounter);

  void recordReadOnlyBatchNativePoolPath() => _incrementEventCounter(MetricsCollectorCore.readOnlyBatchNativePoolPathCounter);

  void recordReadOnlyBatchNativePoolFallback() => _incrementEventCounter(MetricsCollectorCore.readOnlyBatchNativePoolFallbackCounter);

  void recordReadOnlyBatchParallel({
    int? requestedParallelism,
    int? effectiveParallelism,
  }) {
    _incrementEventCounter(MetricsCollectorCore.readOnlyBatchParallelCounter);
    if (requestedParallelism != null) {
      _readOnlyBatchParallelLastRequested = requestedParallelism;
    }
    if (effectiveParallelism != null) {
      _readOnlyBatchParallelLastEffective = effectiveParallelism;
    }
    if (requestedParallelism != null && effectiveParallelism != null && effectiveParallelism < requestedParallelism) {
      _incrementEventCounter(MetricsCollectorCore.readOnlyBatchParallelCappedCounter);
      recordDiagnosticReason(
        category: 'batch',
        reason: RpcSqlDiagnosticsConstants.readOnlyParallelCappedReason,
      );
    }
  }

  void recordDirectConnectionAcquireTimeout() => _incrementEventCounter(MetricsCollectorCore.directConnectionAcquireTimeoutCounter);

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

  void recordPoolReleaseFailure() => _incrementEventCounter(MetricsCollectorCore.poolReleaseFailureCounter);

  void recordPoolDiscardInflightStarted() {
    _poolDiscardInflight++;
    _eventCounters[MetricsCollectorCore.poolDiscardInflightCounter] = _poolDiscardInflight;
  }

  void recordPoolDiscardInflightCompleted() {
    if (_poolDiscardInflight > 0) {
      _poolDiscardInflight--;
    }
    _eventCounters[MetricsCollectorCore.poolDiscardInflightCounter] = _poolDiscardInflight;
  }

  void recordPoolDiscardReconciliationStale() => _incrementEventCounter(MetricsCollectorCore.poolDiscardReconciliationStaleCounter);

  void recordPoolDiscardReconciliationRemediated() =>
      _incrementEventCounter(MetricsCollectorCore.poolDiscardReconciliationRemediatedCounter);

  void recordPoolDiscardReconciliationForceRelease() =>
      _incrementEventCounter(MetricsCollectorCore.poolDiscardReconciliationForceReleaseCounter);

  void recordBulkInsertChunked() => _incrementEventCounter(MetricsCollectorCore.bulkInsertChunkedCounter);

  void recordBulkInsertParallel() => _incrementEventCounter(MetricsCollectorCore.bulkInsertParallelCounter);

  void recordPoolRecycle() => _incrementEventCounter(MetricsCollectorCore.poolRecycleCounter);

  void recordPoolRecycleFailure() => _incrementEventCounter(MetricsCollectorCore.poolRecycleFailureCounter);

  void recordOdbcEventConnectionLost() => _incrementEventCounter(MetricsCollectorCore.odbcEventConnectionLostCounter);

  void recordOdbcEventAutoReconnectAttempted() => _incrementEventCounter(MetricsCollectorCore.odbcEventAutoReconnectAttemptedCounter);

  void recordOdbcEventWorkerRecovered() => _incrementEventCounter(MetricsCollectorCore.odbcEventWorkerRecoveredCounter);

  void recordOdbcEventPoolResize() => _incrementEventCounter(MetricsCollectorCore.odbcEventPoolResizeCounter);

  void recordOdbcEventSlowQueryDetected() => _incrementEventCounter(MetricsCollectorCore.odbcEventSlowQueryDetectedCounter);

  void recordTransactionalBatchReadOnlyInference() =>
      _incrementEventCounter(MetricsCollectorCore.transactionalBatchReadOnlyInferenceCounter);

  void recordTransactionalBatchDeadlineNearStall() =>
      _incrementEventCounter(MetricsCollectorCore.transactionalBatchDeadlineNearStallCounter);

  void recordPoolAcquireTimeout() => _incrementEventCounter(MetricsCollectorCore.poolAcquireTimeoutCounter);

  void recordConnectTimeout() => _incrementEventCounter(MetricsCollectorCore.connectTimeoutCounter);

  void recordQueryTimeout() => _incrementEventCounter(MetricsCollectorCore.queryTimeoutCounter);

  void recordOdbcQueryTimeoutByStage(String stage) {
    final normalizedStage = stage.trim().isEmpty ? 'unknown' : stage.trim();
    _odbcQueryTimeoutByStage[normalizedStage] = (_odbcQueryTimeoutByStage[normalizedStage] ?? 0) + 1;
  }

  void recordPreparedStatementReuse() {
    _incrementEventCounter(MetricsCollectorCore.preparedStatementReuseCounter);
    _incrementEventCounter(MetricsCollectorCore.preparedStatementCacheHitCounter);
  }

  void recordPreparedStatementCacheMiss() => _incrementEventCounter(MetricsCollectorCore.preparedStatementCacheMissCounter);

  void recordStreamCancelRequest() => _incrementEventCounter(MetricsCollectorCore.streamCancelRequestCounter);

  void recordStreamCancelBackpressure() => _incrementEventCounter(MetricsCollectorCore.streamCancelBackpressureCounter);

  void recordStreamCancelDisconnectFailure() => _incrementEventCounter(MetricsCollectorCore.streamCancelDisconnectFailureCounter);

  void recordStreamCancelDisconnectTimeout() => _incrementEventCounter(MetricsCollectorCore.streamCancelDisconnectTimeoutCounter);
}
