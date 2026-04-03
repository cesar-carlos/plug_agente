/// Constantes para configuração de conexões ODBC e Socket.IO.
class ConnectionConstants {
  ConnectionConstants._();

  static const Duration defaultLoginTimeout = Duration(seconds: 30);
  static const Duration defaultQueryTimeout = Duration(seconds: 60);
  static const int defaultMaxResultBufferBytes = 32 * 1024 * 1024;
  static const int defaultInitialResultBufferBytes = 256 * 1024;
  static const int defaultStreamingChunkSizeKb = 1024;

  /// App-level reconnect attempts (ConnectionProvider). Distinct from
  /// [socketReconnectionAttempts] which is the Socket.IO client internal limit.
  static const int defaultMaxReconnectAttempts = 3;
  static const Duration defaultReconnectBackoff = Duration(seconds: 1);
  static const int defaultPoolSize = 4;
  static const Duration defaultPoolAcquireTimeout = Duration(seconds: 30);

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

  /// UTF-8 JSON size above which message tracing replaces the raw payload with a
  /// summary (when `FeatureFlags.enableSocketSummarizeLargePayloadLogs` is on).
  static const int socketLogPayloadSummaryThresholdBytes = 8192;

  /// Outgoing `rpc:response` contract validation is skipped above this UTF-8 JSON
  /// size to limit CPU on huge results (0 disables the soft cap).
  static const int socketOutgoingContractValidationMaxBytes = 2 * 1024 * 1024;
}
