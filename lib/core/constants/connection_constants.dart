import 'dart:developer' as developer;
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:plug_agente/core/config/app_environment.dart';

/// Constantes para configuração de conexões ODBC e Socket.IO.
class ConnectionConstants {
  ConnectionConstants._();

  static String? _optionalEnv(String key) => AppEnvironment.get(key);
  static final Set<String> _loggedInvalidPositiveIntEnvKeys = <String>{};

  /// Hub `GET /api/v1/agents` during backup restore staging (duplicate-session check).
  static const Duration backupRestoreAgentsListTimeout = Duration(seconds: 15);

  static const Duration defaultLoginTimeout = Duration(seconds: 30);
  static const Duration defaultQueryTimeout = Duration(seconds: 60);
  static const Duration defaultTransactionalBatchTimeout = Duration(seconds: 60);
  static const Duration defaultStreamingQueryTimeout = Duration(minutes: 5);
  static const int defaultMaxResultBufferBytes = 64 * 1024 * 1024;
  static const int defaultInitialResultBufferBytes = 256 * 1024;
  static const int defaultStreamingChunkSizeKb = 1024;

  /// App-level burst reconnect attempts (ConnectionProvider) after
  /// [socketReconnectionAttempts] is exhausted. Distinct from
  /// [socketReconnectionAttempts] which is the Socket.IO client internal limit.
  static const int defaultHubRecoveryBurstMaxAttempts = 3;

  /// Interval between automatic hub reconnect attempts after the burst is exhausted.
  static const Duration hubPersistentRetryInterval = Duration(seconds: 45);

  /// Minimum spacing between automatic hard relogin attempts during **persistent**
  /// hub retry. Burst escalation and proactive pre-socket relogin ignore this cooldown.
  static const Duration hubHardReloginCooldown = Duration(seconds: 60);

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

  static int? _positiveIntEnv(String key) {
    final raw = _optionalEnv(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(raw);
    if ((parsed == null || parsed <= 0) && _loggedInvalidPositiveIntEnvKeys.add(key)) {
      developer.log(
        'Ignoring invalid positive integer env override: $key',
        name: 'connection_constants',
        level: 900,
        error: {
          'key': key,
          'value': raw,
        },
      );
    }
    return parsed != null && parsed > 0 ? parsed : null;
  }

  /// ODBC pool size (configurable via ODBC_POOL_SIZE env var).
  static int get poolSize => _positiveIntEnv('ODBC_POOL_SIZE') ?? defaultPoolSize;

  /// Async `odbc_fast` worker count for the current process.
  ///
  /// Defaults to `min(pool size, CPU cores)`, with a minimum of 1. The
  /// `ODBC_ASYNC_WORKER_COUNT` override is capped by the same ceiling to avoid
  /// oversubscribing the native driver beyond the app-level pool.
  static int get odbcAsyncWorkerCount => odbcAsyncWorkerCountForPoolSize(
    poolSize,
    io.Platform.numberOfProcessors,
  );

  static int odbcAsyncWorkerCountForPoolSize(
    int poolSize,
    int processorCount,
  ) {
    final ceiling = _odbcAsyncWorkerCeiling(poolSize, processorCount);
    final override = _positiveIntEnv('ODBC_ASYNC_WORKER_COUNT');
    if (override != null) {
      return math.min(override, ceiling);
    }
    return ceiling;
  }

  static int _odbcAsyncWorkerCeiling(int poolSize, int processorCount) {
    final effectivePoolSize = poolSize > 0 ? poolSize : 1;
    final effectiveProcessorCount = processorCount > 0 ? processorCount : 1;
    return math.max(
      1,
      math.min(effectivePoolSize, effectiveProcessorCount),
    );
  }

  /// Max pending requests accepted by the internal `odbc_fast` async pool.
  static int get odbcAsyncMaxPendingRequests => odbcAsyncMaxPendingRequestsForPoolSize(poolSize);

  static int odbcAsyncMaxPendingRequestsForPoolSize(int poolSize) {
    final override = _positiveIntEnv('ODBC_ASYNC_MAX_PENDING_REQUESTS');
    if (override != null) {
      return override;
    }
    final effectivePoolSize = poolSize > 0 ? poolSize : 1;
    return effectivePoolSize * 4;
  }

  /// SQL execution queue maximum size (configurable via SQL_QUEUE_MAX_SIZE env var).
  static int get sqlQueueMaxSize => int.tryParse(_optionalEnv('SQL_QUEUE_MAX_SIZE') ?? '') ?? 50;

  /// SQL execution queue maximum concurrent workers.
  ///
  /// Defaults to the persisted ODBC pool size used by the runtime dependency
  /// graph. `SQL_QUEUE_MAX_WORKERS` remains an explicit operational override.
  static int get sqlQueueMaxWorkers => sqlQueueMaxWorkersForPoolSize(poolSize);

  static int sqlQueueMaxWorkersForPoolSize(int persistedPoolSize) {
    return _positiveIntEnv('SQL_QUEUE_MAX_WORKERS') ?? (persistedPoolSize > 0 ? persistedPoolSize : defaultPoolSize);
  }

  static int? get directOdbcConnectionMaxConcurrentOverride => _positiveIntEnv('ODBC_DIRECT_CONNECTION_MAX_CONCURRENT');

  /// SQL execution queue enqueue timeout in seconds (configurable via SQL_QUEUE_TIMEOUT_SEC env var).
  static Duration get sqlQueueEnqueueTimeout => Duration(
    seconds: int.tryParse(_optionalEnv('SQL_QUEUE_TIMEOUT_SEC') ?? '') ?? 5,
  );

  /// Circuit breaker failure threshold (configurable via CIRCUIT_BREAKER_FAILURE_THRESHOLD env var).
  static int get circuitBreakerFailureThreshold =>
      int.tryParse(_optionalEnv('CIRCUIT_BREAKER_FAILURE_THRESHOLD') ?? '') ?? 5;

  /// Circuit breaker reset timeout in seconds (configurable via CIRCUIT_BREAKER_RESET_SEC env var).
  static Duration get circuitBreakerResetTimeout => Duration(
    seconds: int.tryParse(_optionalEnv('CIRCUIT_BREAKER_RESET_SEC') ?? '') ?? 30,
  );

  /// Caps parallel connect/disconnect RPCs from the lease ODBC pool into
  /// odbc_fast. Unbounded bursts can queue past the worker's reply deadline.
  static int leasePoolNativeHandshakeConcurrency(int poolSize) {
    // The ODBC async worker stays more reliable when connect/disconnect
    // handshakes are bounded to a small fan-out instead of matching the full
    // app-level pool concurrency.
    if (poolSize < 1) {
      return 1;
    }
    return poolSize > 2 ? 2 : poolSize;
  }

  static int directOdbcConnectionConcurrency(int poolSize) {
    final override = directOdbcConnectionMaxConcurrentOverride;
    final effectivePoolSize = poolSize > 0 ? poolSize : 1;
    if (override != null) {
      return override > effectivePoolSize ? effectivePoolSize : override;
    }
    if (effectivePoolSize < 2) {
      return 1;
    }
    return effectivePoolSize ~/ 2;
  }

  static String directOdbcConnectionCapacityStrategy() {
    return directOdbcConnectionMaxConcurrentOverride == null ? 'half_pool_reserved' : 'env_override';
  }

  static bool directOdbcConnectionOverrideExceedsPool(int? poolSize) {
    final override = directOdbcConnectionMaxConcurrentOverride;
    return override != null && poolSize != null && poolSize > 0 && override > poolSize;
  }

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

  /// Minimum wall-clock interval between HTTP token refresh attempts during hub
  /// recovery (reduces auth endpoint load when the transport is still failing).
  static const Duration hubTokenRefreshMinInterval = Duration(seconds: 5);

  /// When hub reconnect logs omit user-facing error text (`recordErrorMessage: false`),
  /// emit a warning every N failures to avoid log storms during persistent retry.
  static const int hubReconnectFailureLogThrottleStride = 10;

  /// Log hub reachability probes that exceed this duration (diagnostics).
  static const int hubAvailabilityProbeSlowLogThresholdMs = 1000;

  /// UTF-8 JSON size above which message tracing replaces the raw payload with a
  /// summary (when `FeatureFlags.enableSocketSummarizeLargePayloadLogs` is on).
  static const int socketLogPayloadSummaryThresholdBytes = 8192;

  /// Outgoing `rpc:response` contract validation is skipped above this UTF-8 JSON
  /// size to limit CPU on huge results (0 disables the soft cap).
  static const int socketOutgoingContractValidationMaxBytes = 2 * 1024 * 1024;
}
