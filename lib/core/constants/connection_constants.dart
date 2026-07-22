import 'package:plug_agente/core/constants/connection_persistence_constants.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';
import 'package:plug_agente/core/constants/hub_resilience_constants.dart';
import 'package:plug_agente/core/constants/odbc_connection_constants.dart';
import 'package:plug_agente/core/constants/socket_transport_constants.dart';
import 'package:plug_agente/core/constants/sql_queue_constants.dart';

export 'connection_constants_env.dart';
export 'connection_persistence_constants.dart';
export 'hub_resilience_constants.dart';
export 'odbc_connection_constants.dart';
export 'socket_transport_constants.dart';
export 'sql_queue_constants.dart';

/// Constantes para configuração de conexões ODBC e Socket.IO.
///
/// Facade preserving the legacy API; see focused modules exported above.
abstract final class ConnectionConstants {
  ConnectionConstants._();

  // Hub resilience
  static const Duration backupRestoreAgentsListTimeout = HubResilienceConstants.backupRestoreAgentsListTimeout;
  static const Duration agentHubProfileHttpTimeout = HubResilienceConstants.agentHubProfileHttpTimeout;
  static const int defaultHubRecoveryBurstMaxAttempts = HubResilienceConstants.defaultHubRecoveryBurstMaxAttempts;
  static const Duration hubPersistentRetryInterval = HubResilienceConstants.hubPersistentRetryInterval;
  static const Duration hubHardReloginCooldown = HubResilienceConstants.hubHardReloginCooldown;
  static const int hubPersistentRetryMaxFailedTicks = HubResilienceConstants.hubPersistentRetryMaxFailedTicks;
  static const int hubPersistentUnreachableMaxFailedTicks =
      HubResilienceConstants.hubPersistentUnreachableMaxFailedTicks;
  static const String hubPersistentRetryExhaustedMessage = HubResilienceConstants.hubPersistentRetryExhaustedMessage;
  static const int defaultMaxReconnectAttempts = HubResilienceConstants.defaultMaxReconnectAttempts;
  static const Duration hubTokenRefreshMinInterval = HubResilienceConstants.hubTokenRefreshMinInterval;
  static const Duration hubAccessTokenProactiveRefreshMargin =
      HubResilienceConstants.hubAccessTokenProactiveRefreshMargin;
  static const int hubReconnectFailureLogThrottleStride = HubResilienceConstants.hubReconnectFailureLogThrottleStride;
  static const int hubAvailabilityProbeSlowLogThresholdMs =
      HubResilienceConstants.hubAvailabilityProbeSlowLogThresholdMs;
  static const int socketReconnectionAttempts = HubResilienceConstants.socketReconnectionAttempts;
  static const int socketReconnectionDelayMs = HubResilienceConstants.socketReconnectionDelayMs;
  static const int socketReconnectionDelayMaxMs = HubResilienceConstants.socketReconnectionDelayMaxMs;

  // ODBC
  static const Duration defaultLoginTimeout = OdbcConnectionConstants.defaultLoginTimeout;
  static const Duration defaultQueryTimeout = OdbcConnectionConstants.defaultQueryTimeout;
  static const Duration defaultTransactionalBatchTimeout = OdbcConnectionConstants.defaultTransactionalBatchTimeout;
  static const Duration defaultStreamingQueryTimeout = OdbcConnectionConstants.defaultStreamingQueryTimeout;
  static const int defaultMaxResultBufferBytes = OdbcConnectionConstants.defaultMaxResultBufferBytes;
  static const int minMaxResultBufferMb = OdbcConnectionConstants.minMaxResultBufferMb;
  static const int maxMaxResultBufferMb = OdbcConnectionConstants.maxMaxResultBufferMb;
  static const int maxAutoExpandedResultBufferBytes = OdbcConnectionConstants.maxAutoExpandedResultBufferBytes;
  static const int defaultSqlExecuteMaterializedMaxRows = OdbcConnectionConstants.defaultSqlExecuteMaterializedMaxRows;
  static const int defaultSqlExecuteMaterializedMaxEstimatedBytes =
      OdbcConnectionConstants.defaultSqlExecuteMaterializedMaxEstimatedBytes;
  static const int defaultSqlExecuteMaterializedEstimatedBytesPerRow =
      OdbcConnectionConstants.defaultSqlExecuteMaterializedEstimatedBytesPerRow;
  static const int defaultInitialResultBufferBytes = OdbcConnectionConstants.defaultInitialResultBufferBytes;
  static const int defaultStreamingChunkSizeKb = OdbcConnectionConstants.defaultStreamingChunkSizeKb;
  static const Duration defaultStreamingConnectReuseTtl = OdbcConnectionConstants.defaultStreamingConnectReuseTtl;
  static const int defaultStreamingConnectReuseMaxEntries =
      OdbcConnectionConstants.defaultStreamingConnectReuseMaxEntries;
  static const bool defaultStreamingConnectReuseEnabled = OdbcConnectionConstants.defaultStreamingConnectReuseEnabled;
  static const Duration defaultReconnectBackoff = OdbcConnectionConstants.defaultReconnectBackoff;
  static const int defaultPoolSize = OdbcConnectionConstants.defaultPoolSize;
  static const Duration defaultPoolAcquireTimeout = OdbcConnectionConstants.defaultPoolAcquireTimeout;
  static const int defaultMaxConcurrentConnectionTests = OdbcConnectionConstants.defaultMaxConcurrentConnectionTests;
  static const Duration connectionTestAcquireTimeout = OdbcConnectionConstants.connectionTestAcquireTimeout;
  static const Duration defaultNativePoolIdleTimeout = OdbcConnectionConstants.defaultNativePoolIdleTimeout;
  static const Duration defaultNativePoolMaxLifetime = OdbcConnectionConstants.defaultNativePoolMaxLifetime;
  static const Duration defaultNativePoolConnectionTimeout = OdbcConnectionConstants.defaultNativePoolConnectionTimeout;
  static int get poolSize => OdbcConnectionConstants.poolSize;
  static int get odbcAsyncWorkerCount => OdbcConnectionConstants.odbcAsyncWorkerCount;
  static int odbcAsyncWorkerCountForPoolSize(int poolSize, int processorCount) =>
      OdbcConnectionConstants.odbcAsyncWorkerCountForPoolSize(poolSize, processorCount);
  static int get odbcAsyncMaxPendingRequests => SqlQueueConstants.odbcAsyncMaxPendingRequests;
  static int odbcAsyncMaxPendingRequestsForPoolSize(int poolSize) =>
      SqlQueueConstants.odbcAsyncMaxPendingRequestsForPoolSize(poolSize);
  static int? get directOdbcConnectionMaxConcurrentOverride =>
      OdbcConnectionConstants.directOdbcConnectionMaxConcurrentOverride;
  static int get sqlExecuteMaterializedMaxRows => OdbcConnectionConstants.sqlExecuteMaterializedMaxRows;
  static int get sqlExecuteMaterializedMaxEstimatedBytes =>
      OdbcConnectionConstants.sqlExecuteMaterializedMaxEstimatedBytes;
  static int get sqlExecuteMaterializedEstimatedBytesPerRow =>
      OdbcConnectionConstants.sqlExecuteMaterializedEstimatedBytesPerRow;
  static int leasePoolNativeHandshakeConcurrency(int poolSize) =>
      OdbcConnectionConstants.leasePoolNativeHandshakeConcurrency(poolSize);
  static int directOdbcConnectionConcurrency(int poolSize) =>
      OdbcConnectionConstants.directOdbcConnectionConcurrency(poolSize);
  static int directOdbcOperationClassCap(DirectOdbcOperationClass operationClass, int globalMaxConcurrent) =>
      OdbcConnectionConstants.directOdbcOperationClassCap(operationClass, globalMaxConcurrent);
  static const int defaultBulkInsertChunkRowCount = OdbcConnectionConstants.defaultBulkInsertChunkRowCount;
  static const int defaultBulkInsertParallelRowThreshold =
      OdbcConnectionConstants.defaultBulkInsertParallelRowThreshold;
  static const bool defaultBulkInsertParallelEnabled = OdbcConnectionConstants.defaultBulkInsertParallelEnabled;
  static const bool defaultReadOnlyBatchNativePoolEnabled =
      OdbcConnectionConstants.defaultReadOnlyBatchNativePoolEnabled;
  static const bool defaultNativeWarmUpEnabled = OdbcConnectionConstants.defaultNativeWarmUpEnabled;
  static const int defaultBatchBulkInsertRecommendationThreshold =
      OdbcConnectionConstants.defaultBatchBulkInsertRecommendationThreshold;
  static const int defaultBatchBulkInsertRouteThreshold = OdbcConnectionConstants.defaultBatchBulkInsertRouteThreshold;
  static int get bulkInsertChunkRowCount => OdbcConnectionConstants.bulkInsertChunkRowCount;
  static bool get readOnlyBatchNativePoolEnabled => OdbcConnectionConstants.readOnlyBatchNativePoolEnabled;
  static bool get bulkInsertParallelEnabled => OdbcConnectionConstants.bulkInsertParallelEnabled;
  static int get bulkInsertParallelRowThreshold => OdbcConnectionConstants.bulkInsertParallelRowThreshold;
  static int bulkInsertParallelismForPoolSize(int poolSize) =>
      OdbcConnectionConstants.bulkInsertParallelismForPoolSize(poolSize);
  static bool get nativeWarmUpEnabled => OdbcConnectionConstants.nativeWarmUpEnabled;
  static int get batchBulkInsertRecommendationThreshold =>
      OdbcConnectionConstants.batchBulkInsertRecommendationThreshold;
  static int get batchBulkInsertRouteThreshold => OdbcConnectionConstants.batchBulkInsertRouteThreshold;
  static int readOnlyBatchParallelismForPoolSize(int poolSize) =>
      OdbcConnectionConstants.readOnlyBatchParallelismForPoolSize(poolSize);
  static String directOdbcConnectionCapacityStrategy() =>
      OdbcConnectionConstants.directOdbcConnectionCapacityStrategy();
  static bool directOdbcConnectionOverrideExceedsPool(int? poolSize) =>
      OdbcConnectionConstants.directOdbcConnectionOverrideExceedsPool(poolSize);
  static const int defaultPlaygroundStreamingMaxResultRows =
      OdbcConnectionConstants.defaultPlaygroundStreamingMaxResultRows;
  static int get playgroundStreamingMaxResultRows => OdbcConnectionConstants.playgroundStreamingMaxResultRows;
  static const int defaultPlaygroundStreamingUiWindowRows =
      OdbcConnectionConstants.defaultPlaygroundStreamingUiWindowRows;
  static int get playgroundStreamingUiWindowRows => OdbcConnectionConstants.playgroundStreamingUiWindowRows;
  static bool get streamingConnectReuseEnabled => OdbcConnectionConstants.streamingConnectReuseEnabled;
  static Duration get streamingConnectReuseTtl => OdbcConnectionConstants.streamingConnectReuseTtl;
  static int get streamingConnectReuseMaxEntries => OdbcConnectionConstants.streamingConnectReuseMaxEntries;

  // SQL queue
  static const int defaultSqlQueueMaxSize = SqlQueueConstants.defaultSqlQueueMaxSize;
  static int get sqlQueueMaxSize => SqlQueueConstants.sqlQueueMaxSize;
  static int get rpcSqlExecuteConcurrencySoftLimit => SqlQueueConstants.rpcSqlExecuteConcurrencySoftLimit;
  static int get sqlQueueMaxWorkers => SqlQueueConstants.sqlQueueMaxWorkers;
  static int sqlQueueMaxWorkersForPoolSize(int persistedPoolSize) =>
      SqlQueueConstants.sqlQueueMaxWorkersForPoolSize(persistedPoolSize);
  static int sqlQueueMaxBatchWorkersForWorkers(int maxWorkers, {int? persistedPoolSize}) =>
      SqlQueueConstants.sqlQueueMaxBatchWorkersForWorkers(maxWorkers, persistedPoolSize: persistedPoolSize);
  static int sqlQueueMaxLongQueryWorkersForWorkers(int maxWorkers, {int? persistedPoolSize}) =>
      SqlQueueConstants.sqlQueueMaxLongQueryWorkersForWorkers(maxWorkers, persistedPoolSize: persistedPoolSize);
  static int sqlQueueMaxStreamingWorkersForWorkers(int maxWorkers, {int? persistedPoolSize}) =>
      SqlQueueConstants.sqlQueueMaxStreamingWorkersForWorkers(maxWorkers, persistedPoolSize: persistedPoolSize);
  static int sqlQueueMaxNonQueryWorkersForWorkers(int maxWorkers, {int? persistedPoolSize}) =>
      SqlQueueConstants.sqlQueueMaxNonQueryWorkersForWorkers(maxWorkers, persistedPoolSize: persistedPoolSize);
  static Duration get sqlQueueEnqueueTimeout => SqlQueueConstants.sqlQueueEnqueueTimeout;
  static int get circuitBreakerFailureThreshold => SqlQueueConstants.circuitBreakerFailureThreshold;
  static Duration get circuitBreakerResetTimeout => SqlQueueConstants.circuitBreakerResetTimeout;
  static bool isSqlQueueDepthAboveOdbcAsyncPending({
    required int sqlQueueMaxSize,
    required int asyncMaxPendingRequests,
  }) => SqlQueueConstants.isSqlQueueDepthAboveOdbcAsyncPending(
    sqlQueueMaxSize: sqlQueueMaxSize,
    asyncMaxPendingRequests: asyncMaxPendingRequests,
  );

  // Socket transport
  static const int socketConnectionTimeoutMs = SocketTransportConstants.socketConnectionTimeoutMs;
  static const int socketAckTimeoutMs = SocketTransportConstants.socketAckTimeoutMs;
  static const int capabilitiesTimeoutMs = SocketTransportConstants.capabilitiesTimeoutMs;
  static const int capabilitiesMaxReRegisterAttempts = SocketTransportConstants.capabilitiesMaxReRegisterAttempts;
  static const int capabilitiesNegotiationWatchdogMarginMs =
      SocketTransportConstants.capabilitiesNegotiationWatchdogMarginMs;
  static int get capabilitiesNegotiationWatchdogMs => SocketTransportConstants.capabilitiesNegotiationWatchdogMs;
  static const Duration socketHeartbeatInterval = SocketTransportConstants.socketHeartbeatInterval;
  static const Duration socketHeartbeatAckTimeout = SocketTransportConstants.socketHeartbeatAckTimeout;
  static const int socketMaxMissedHeartbeats = SocketTransportConstants.socketMaxMissedHeartbeats;
  static const int maxConnectionPools = SocketTransportConstants.maxConnectionPools;
  static const int maxBackpressureChunkQueueSize = SocketTransportConstants.maxBackpressureChunkQueueSize;
  static const int defaultMaxConcurrentRpcHandlersHeadroom =
      SocketTransportConstants.defaultMaxConcurrentRpcHandlersHeadroom;
  static int get maxConcurrentRpcHandlers => SocketTransportConstants.maxConcurrentRpcHandlers;
  static const int maxConcurrentRpcStreams = SocketTransportConstants.maxConcurrentRpcStreams;
  static const Duration rpcStreamEmitterMaxIdle = SocketTransportConstants.rpcStreamEmitterMaxIdle;
  static const int receivePipelineCacheMaxEntries = SocketTransportConstants.receivePipelineCacheMaxEntries;
  static const int clientTokenGetPolicyDefaultMaxPerMinute =
      SocketTransportConstants.clientTokenGetPolicyDefaultMaxPerMinute;
  static const int clientTokenGetPolicyDefaultMaxScopeKeys =
      SocketTransportConstants.clientTokenGetPolicyDefaultMaxScopeKeys;
  static const int socketLogPayloadSummaryThresholdBytes =
      SocketTransportConstants.socketLogPayloadSummaryThresholdBytes;
  static const int defaultSchemaValidationSkipAboveBytes =
      SocketTransportConstants.defaultSchemaValidationSkipAboveBytes;
  static int get schemaValidationSkipAboveBytes => SocketTransportConstants.schemaValidationSkipAboveBytes;
  static const int socketOutgoingContractValidationMaxBytes =
      SocketTransportConstants.socketOutgoingContractValidationMaxBytes;
  static const int defaultGzipIsolateThresholdBytes = SocketTransportConstants.defaultGzipIsolateThresholdBytes;
  static const int streamingChunkJsonIsolateThresholdBytes =
      SocketTransportConstants.streamingChunkJsonIsolateThresholdBytes;
  static const int streamingChunkRowIsolateThreshold = SocketTransportConstants.streamingChunkRowIsolateThreshold;
  static const int defaultRpcChunkJsonIsolateThresholdBytes =
      SocketTransportConstants.defaultRpcChunkJsonIsolateThresholdBytes;
  static int get rpcChunkJsonIsolateThresholdBytes => SocketTransportConstants.rpcChunkJsonIsolateThresholdBytes;
  static const int defaultRpcChunkGzipIsolateThresholdBytes =
      SocketTransportConstants.defaultRpcChunkGzipIsolateThresholdBytes;
  static int get rpcChunkGzipIsolateThresholdBytes => SocketTransportConstants.rpcChunkGzipIsolateThresholdBytes;
  static const int defaultRpcChunkCompressionThresholdBytes =
      SocketTransportConstants.defaultRpcChunkCompressionThresholdBytes;
  static int get rpcChunkCompressionThresholdBytes => SocketTransportConstants.rpcChunkCompressionThresholdBytes;
  static const int defaultRpcChunkRowIsolateThreshold = SocketTransportConstants.defaultRpcChunkRowIsolateThreshold;
  static int get rpcChunkRowIsolateThreshold => SocketTransportConstants.rpcChunkRowIsolateThreshold;
  static const bool defaultRpcChunkColumnarGzipEnabled = SocketTransportConstants.defaultRpcChunkColumnarGzipEnabled;
  static bool get rpcChunkColumnarGzipEnabled => SocketTransportConstants.rpcChunkColumnarGzipEnabled;
  static const int defaultProtocolMetricsRpcChunkSampleRate =
      SocketTransportConstants.defaultProtocolMetricsRpcChunkSampleRate;
  static int get protocolMetricsRpcChunkSampleRate => SocketTransportConstants.protocolMetricsRpcChunkSampleRate;
  static const int defaultAuthorizationDecisionCacheTtlSeconds =
      SocketTransportConstants.defaultAuthorizationDecisionCacheTtlSeconds;
  static Duration get authorizationDecisionCacheTtl => SocketTransportConstants.authorizationDecisionCacheTtl;
  static int get gzipIsolateThresholdBytes => SocketTransportConstants.gzipIsolateThresholdBytes;
  static const int defaultSigningIsolateThresholdBytes = SocketTransportConstants.defaultSigningIsolateThresholdBytes;
  static int get signingIsolateThresholdBytes => SocketTransportConstants.signingIsolateThresholdBytes;
  static const int defaultRecommendedStreamPullWindowSize =
      SocketTransportConstants.defaultRecommendedStreamPullWindowSize;
  static int get recommendedStreamPullWindowSize => SocketTransportConstants.recommendedStreamPullWindowSize;
  static const Duration rpcAckCoalesceFlushInterval = SocketTransportConstants.rpcAckCoalesceFlushInterval;
  static const int rpcAckCoalesceMaxBatch = SocketTransportConstants.rpcAckCoalesceMaxBatch;

  // Persistence purge / retention
  static const Duration rpcIdempotencyExpiredPurgeInterval =
      ConnectionPersistenceConstants.rpcIdempotencyExpiredPurgeInterval;
  static Duration get rpcIdempotencyEntryTtl => ConnectionPersistenceConstants.rpcIdempotencyEntryTtl;
  static Duration get agentActionRpcIdempotencyEntryTtl =>
      ConnectionPersistenceConstants.agentActionRpcIdempotencyEntryTtl;
  static const Duration agentActionRemoteAuditPurgeInterval =
      ConnectionPersistenceConstants.agentActionRemoteAuditPurgeInterval;
  static Duration get agentActionRemoteAuditRetention => ConnectionPersistenceConstants.agentActionRemoteAuditRetention;
  static const Duration agentActionExecutionPurgeInterval =
      ConnectionPersistenceConstants.agentActionExecutionPurgeInterval;
  static Duration get agentActionExecutionRetention => ConnectionPersistenceConstants.agentActionExecutionRetention;
  static const Duration agentActionCapturedOutputPurgeInterval =
      ConnectionPersistenceConstants.agentActionCapturedOutputPurgeInterval;
  static Duration get agentActionCapturedOutputRetention =>
      ConnectionPersistenceConstants.agentActionCapturedOutputRetention;
}
