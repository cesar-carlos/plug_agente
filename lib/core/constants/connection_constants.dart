/// Constantes para configuração de conexões ODBC e Socket.IO.
class ConnectionConstants {
  ConnectionConstants._();

  static const Duration defaultLoginTimeout = Duration(seconds: 30);
  static const Duration defaultQueryTimeout = Duration(seconds: 60);
  static const Duration defaultTransactionalBatchTimeout = Duration(seconds: 60);
  static const Duration defaultStreamingQueryTimeout = Duration(minutes: 5);
  static const int defaultMaxResultBufferBytes = 32 * 1024 * 1024;
  static const int defaultInitialResultBufferBytes = 256 * 1024;
  static const int defaultStreamingChunkSizeKb = 1024;

  /// App-level burst reconnect attempts (ConnectionProvider) after
  /// [socketReconnectionAttempts] is exhausted. Distinct from
  /// [socketReconnectionAttempts] which is the Socket.IO client internal limit.
  static const int defaultHubRecoveryBurstMaxAttempts = 3;

  /// Interval between automatic hub reconnect attempts after the burst is exhausted.
  static const Duration hubPersistentRetryInterval = Duration(seconds: 45);

  /// Max failed persistent reconnect ticks before giving up (`0` = unlimited).
  static const int hubPersistentRetryMaxFailedTicks = 120;

  /// User-facing message when [hubPersistentRetryMaxFailedTicks] is exceeded (English;
  /// mirror in ARB for localized surfaces).
  static const String hubPersistentRetryExhaustedMessage =
      'Could not reach the hub after many attempts. Check the server URL, network, and '
      'sign-in, then tap Connect.';

  /// Legacy name; same as [defaultHubRecoveryBurstMaxAttempts] (ODBC pool options).
  static const int defaultMaxReconnectAttempts = defaultHubRecoveryBurstMaxAttempts;
  static const Duration defaultReconnectBackoff = Duration(seconds: 1);
  static const int defaultPoolSize = 4;
  static const Duration defaultPoolAcquireTimeout = Duration(seconds: 30);
  static const Duration defaultNativePoolIdleTimeout = Duration(minutes: 5);
  static const Duration defaultNativePoolMaxLifetime = Duration(hours: 1);
  static const Duration defaultNativePoolConnectionTimeout = defaultPoolAcquireTimeout;

  static const int socketConnectionTimeoutMs = 10000;
  static const int socketAckTimeoutMs = 8000;

  /// Timeout for hub to respond with agent:capabilities after agent:register.
  static const int capabilitiesTimeoutMs = 8000;

  /// Max agent:register retries before forcing reconnect when capabilities missing.
  static const int capabilitiesMaxReRegisterAttempts = 2;

  /// Socket.IO client internal reconnection attempts (transport-level).
  static const int socketReconnectionAttempts = 15;
  static const int socketReconnectionDelayMs = 5000;
  static const int socketReconnectionDelayMaxMs = 60000;

  static const Duration socketHeartbeatInterval = Duration(seconds: 20);
  static const Duration socketHeartbeatAckTimeout = Duration(seconds: 8);
  static const int socketMaxMissedHeartbeats = 2;

  static const int maxConnectionPools = 64;
  static const int maxBackpressureChunkQueueSize = 1000;

  /// Max rows kept in Playground UI during ODBC streaming (memory / grid cost).
  static const int playgroundStreamingMaxResultRows = 100000;

  /// Max in-flight `rpc:request` handlers per socket connection (backpressure).
  static const int maxConcurrentRpcHandlers = 32;

  /// Max simultaneously registered RPC streaming emitters per socket connection.
  /// Each emitter holds buffered chunks awaiting `rpc:stream.pull` from the hub;
  /// the cap protects memory if streams never receive a final pull/complete.
  static const int maxConcurrentRpcStreams = 64;

  /// Idle timeout for an RPC streaming emitter. If the hub does not call
  /// `rpc:stream.pull` within this window after the last activity, the emitter
  /// is unregistered defensively to avoid leaks across long-lived sockets.
  static const Duration rpcStreamEmitterMaxIdle = Duration(seconds: 300);

  /// Max distinct receive-pipeline entries cached per socket connection.
  /// Each entry is keyed by `(encoding, compression, schemaVersion, threshold)`.
  /// LRU eviction; raise this if `pipeline_cache_eviction` metrics show churn.
  static const int receivePipelineCacheMaxEntries = 16;

  /// Default max successful `client_token.getPolicy` calls per minute per agent+credential scope.
  /// Override with env `CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE` (`0` = unlimited).
  static const int clientTokenGetPolicyDefaultMaxPerMinute = 120;

  /// Max distinct agent+credential scopes tracked by the getPolicy rate limiter at once.
  /// Override with env `CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS` (`0` = no cap on distinct keys).
  static const int clientTokenGetPolicyDefaultMaxScopeKeys = 8192;

  /// UTF-8 JSON size above which message tracing replaces the raw payload with a
  /// summary (when `FeatureFlags.enableSocketSummarizeLargePayloadLogs` is on).
  static const int socketLogPayloadSummaryThresholdBytes = 8192;

  /// Outgoing `rpc:response` contract validation is skipped above this UTF-8 JSON
  /// size to limit CPU on huge results (0 disables the soft cap).
  static const int socketOutgoingContractValidationMaxBytes = 2 * 1024 * 1024;
}
