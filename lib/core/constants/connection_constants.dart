import 'dart:developer' as developer;
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart' show IIdempotencyStore;

/// Constantes para configuração de conexões ODBC e Socket.IO.
class ConnectionConstants {
  ConnectionConstants._();

  static String? _optionalEnv(String key) => AppEnvironment.get(key);
  static final Set<String> _loggedInvalidPositiveIntEnvKeys = <String>{};

  /// Hub `GET /api/v1/agents` during backup restore staging (duplicate-session check).
  static const Duration backupRestoreAgentsListTimeout = Duration(seconds: 15);

  /// Hub agent profile PATCH/GET (`/api/v1/agents/{id}/profile`).
  static const Duration agentHubProfileHttpTimeout = Duration(seconds: 30);

  static const Duration defaultLoginTimeout = Duration(seconds: 30);
  static const Duration defaultQueryTimeout = Duration(seconds: 60);
  static const Duration defaultTransactionalBatchTimeout = Duration(seconds: 60);
  static const Duration defaultStreamingQueryTimeout = Duration(minutes: 5);
  static const int defaultMaxResultBufferBytes = 64 * 1024 * 1024;
  static const int defaultSqlExecuteMaterializedMaxRows = 5000;
  static const int defaultSqlExecuteMaterializedMaxEstimatedBytes = 16 * 1024 * 1024;
  static const int defaultSqlExecuteMaterializedEstimatedBytesPerRow = 512;
  static const int defaultInitialResultBufferBytes = 256 * 1024;
  static const int defaultStreamingChunkSizeKb = 1024;
  static const Duration defaultStreamingConnectReuseTtl = Duration(seconds: 30);
  static const int defaultStreamingConnectReuseMaxEntries = 8;
  static const bool defaultStreamingConnectReuseEnabled = true;

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
  static const int hubPersistentRetryMaxFailedTicks = 0;

  /// User-facing message when [hubPersistentRetryMaxFailedTicks] is exceeded (English;
  /// mirror in ARB for localized surfaces).
  static const String hubPersistentRetryExhaustedMessage =
      'Could not reach the hub after many attempts. Check the server URL, network, and '
      'sign-in, then tap Connect.';

  /// Legacy name; same as [defaultHubRecoveryBurstMaxAttempts] (ODBC pool options).
  static const int defaultMaxReconnectAttempts = defaultHubRecoveryBurstMaxAttempts;
  static const Duration defaultReconnectBackoff = Duration(seconds: 1);
  static const int defaultPoolSize = 8;
  static const int defaultSqlQueueMaxSize = 16;
  static const Duration defaultPoolAcquireTimeout = Duration(seconds: 30);

  /// Max concurrent ODBC connection tests (UI/RPC probes bypass the SQL queue).
  static const int defaultMaxConcurrentConnectionTests = 2;

  static const Duration connectionTestAcquireTimeout = Duration(seconds: 10);
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
    // Must cover at least as many slots as the SQL queue dispatches concurrently.
    // If SQL_QUEUE_MAX_WORKERS is raised above the default (poolSize), the ODBC
    // pending limit must keep up or failFast will reject dispatched requests.
    return math.max(
      effectivePoolSize * 4,
      sqlQueueMaxWorkersForPoolSize(effectivePoolSize),
    );
  }

  /// SQL execution queue maximum size (configurable via SQL_QUEUE_MAX_SIZE env var).
  static int get sqlQueueMaxSize => _positiveIntEnv('SQL_QUEUE_MAX_SIZE') ?? defaultSqlQueueMaxSize;

  /// Soft in-flight `sql.execute` RPC limit per client token (or agent) scope.
  ///
  /// Matches SQL queue backpressure capacity: concurrent dispatch slots plus
  /// queue depth (`sqlQueueMaxWorkers + sqlQueueMaxSize`).
  static int get rpcSqlExecuteConcurrencySoftLimit => sqlQueueMaxWorkers + sqlQueueMaxSize;

  /// SQL execution queue maximum concurrent workers.
  ///
  /// Defaults to the persisted ODBC pool size used by the runtime dependency
  /// graph. `SQL_QUEUE_MAX_WORKERS` remains an explicit operational override.
  static int get sqlQueueMaxWorkers => sqlQueueMaxWorkersForPoolSize(poolSize);

  static int sqlQueueMaxWorkersForPoolSize(int persistedPoolSize) {
    return _positiveIntEnv('SQL_QUEUE_MAX_WORKERS') ?? (persistedPoolSize > 0 ? persistedPoolSize : defaultPoolSize);
  }

  static int sqlQueueMaxBatchWorkersForWorkers(
    int maxWorkers, {
    int? persistedPoolSize,
  }) {
    return _positiveIntEnv('SQL_QUEUE_MAX_BATCH_WORKERS') ??
        _sqlQueuePerKindWorkerCap(
          maxWorkers: maxWorkers,
          persistedPoolSize: persistedPoolSize,
          operationClass: DirectOdbcOperationClass.batchTransaction,
        );
  }

  static int sqlQueueMaxLongQueryWorkersForWorkers(
    int maxWorkers, {
    int? persistedPoolSize,
  }) {
    return _positiveIntEnv('SQL_QUEUE_MAX_LONG_QUERY_WORKERS') ??
        _sqlQueuePerKindWorkerCap(
          maxWorkers: maxWorkers,
          persistedPoolSize: persistedPoolSize,
          operationClass: DirectOdbcOperationClass.streaming,
        );
  }

  static int sqlQueueMaxStreamingWorkersForWorkers(
    int maxWorkers, {
    int? persistedPoolSize,
  }) {
    return _positiveIntEnv('SQL_QUEUE_MAX_STREAMING_WORKERS') ??
        _sqlQueuePerKindWorkerCap(
          maxWorkers: maxWorkers,
          persistedPoolSize: persistedPoolSize,
          operationClass: DirectOdbcOperationClass.streaming,
        );
  }

  static int sqlQueueMaxNonQueryWorkersForWorkers(
    int maxWorkers, {
    int? persistedPoolSize,
  }) {
    return _positiveIntEnv('SQL_QUEUE_MAX_NON_QUERY_WORKERS') ??
        _sqlQueuePerKindWorkerCap(
          maxWorkers: maxWorkers,
          persistedPoolSize: persistedPoolSize,
          operationClass: DirectOdbcOperationClass.general,
        );
  }

  /// Per-kind SQL queue worker cap aligned with the direct ODBC connection limiter.
  ///
  /// Uses `min(maxWorkers ~/ 2, directOdbcOperationClassCap(...))` so queue
  /// dispatch for batch/streaming workloads cannot exceed the direct ODBC budget.
  static int _sqlQueuePerKindWorkerCap({
    required int maxWorkers,
    required DirectOdbcOperationClass operationClass,
    int? persistedPoolSize,
  }) {
    final effectiveWorkers = maxWorkers > 0 ? maxWorkers : 1;
    final halfWorkers = math.max(1, effectiveWorkers ~/ 2);
    final poolSize = persistedPoolSize ?? effectiveWorkers;
    final directGlobalBudget = directOdbcConnectionConcurrency(poolSize);
    final directClassCap = directOdbcOperationClassCap(operationClass, directGlobalBudget);
    return math.min(halfWorkers, directClassCap);
  }

  static int? get directOdbcConnectionMaxConcurrentOverride => _positiveIntEnv('ODBC_DIRECT_CONNECTION_MAX_CONCURRENT');

  /// Hub `sql.execute` row cap above which materialized responses are rejected when
  /// streaming chunks are negotiated. Override with `SQL_EXECUTE_MATERIALIZED_MAX_ROWS`.
  static int get sqlExecuteMaterializedMaxRows =>
      _positiveIntEnv('SQL_EXECUTE_MATERIALIZED_MAX_ROWS') ?? defaultSqlExecuteMaterializedMaxRows;

  /// Estimated byte budget for materialized `sql.execute` before forcing DB streaming
  /// or rejecting. Override with `SQL_EXECUTE_MATERIALIZED_MAX_BYTES`.
  static int get sqlExecuteMaterializedMaxEstimatedBytes =>
      _positiveIntEnv('SQL_EXECUTE_MATERIALIZED_MAX_BYTES') ?? defaultSqlExecuteMaterializedMaxEstimatedBytes;

  /// Rough bytes-per-row estimate used with [sqlExecuteMaterializedMaxEstimatedBytes].
  /// Override with `SQL_EXECUTE_MATERIALIZED_BYTES_PER_ROW`.
  static int get sqlExecuteMaterializedEstimatedBytesPerRow =>
      _positiveIntEnv('SQL_EXECUTE_MATERIALIZED_BYTES_PER_ROW') ??
      defaultSqlExecuteMaterializedEstimatedBytesPerRow;

  /// SQL execution queue **wait** timeout (configurable via `SQL_QUEUE_TIMEOUT_SEC`).
  ///
  /// Bounds only how long a request may wait for a worker slot before the caller
  /// receives a queue-timeout failure. It does **not** cancel ODBC work once a
  /// worker has started: materialized `sql.execute` and streaming observe a
  /// cooperative cancellation token wired at the gateway layer, and still rely
  /// on per-request ODBC timeouts when native work is already in flight. A queue-wait timeout that races with worker start can
  /// leave an in-flight ODBC task running ("ghost query"); see `SqlExecutionQueue`
  /// and metric `sql_queue_timeout_after_worker_started`.
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
    // Formula: min(max(2, poolSize ~/ 5), 4) — scales gently with pool size:
    //   pool  1-9  → 2  (same as before)
    //   pool 10-14 → 2
    //   pool 15-19 → 3
    //   pool 20    → 4
    if (poolSize < 1) {
      return 1;
    }
    return math.min(math.max(2, poolSize ~/ 5), 4);
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

  /// Per-class ceiling for the direct ODBC connection limiter within the global budget.
  static int directOdbcOperationClassCap(
    DirectOdbcOperationClass operationClass,
    int globalMaxConcurrent,
  ) {
    final effectiveGlobal = globalMaxConcurrent < 1 ? 1 : globalMaxConcurrent;
    return switch (operationClass) {
      DirectOdbcOperationClass.streaming => math.max(1, (effectiveGlobal + 1) ~/ 2),
      DirectOdbcOperationClass.bulk => math.max(1, effectiveGlobal ~/ 2),
      DirectOdbcOperationClass.batchTransaction => math.max(1, effectiveGlobal ~/ 2),
      DirectOdbcOperationClass.general => effectiveGlobal,
    };
  }

  static const int defaultBulkInsertChunkRowCount = 10000;
  static const int defaultBulkInsertParallelRowThreshold = 50000;
  static const bool defaultBulkInsertParallelEnabled = true;
  static const bool defaultReadOnlyBatchNativePoolEnabled = false;
  static const bool defaultNativeWarmUpEnabled = true;
  static const int defaultBatchBulkInsertRecommendationThreshold = 50;
  static const int defaultBatchBulkInsertRouteThreshold = 50;

  /// Rows per native bulk-insert chunk when the request exceeds this size.
  ///
  /// Override with env `ODBC_BULK_INSERT_CHUNK_ROWS` (positive integer).
  static int get bulkInsertChunkRowCount =>
      _positiveIntEnv('ODBC_BULK_INSERT_CHUNK_ROWS') ?? defaultBulkInsertChunkRowCount;

  /// When true, homogeneous read-only parallel batches may acquire worker
  /// connections through the native-compatible ODBC pool path.
  ///
  /// Override with env `ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED` (`true`/`false`).
  static bool get readOnlyBatchNativePoolEnabled {
    final raw = _optionalEnv('ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED');
    if (raw == null || raw.isEmpty) {
      return defaultReadOnlyBatchNativePoolEnabled;
    }
    final normalized = raw.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultReadOnlyBatchNativePoolEnabled;
  }

  /// When true, large SQL Server bulk inserts may use `bulkInsertParallel`.
  ///
  /// Override with env `ODBC_BULK_INSERT_PARALLEL_ENABLED` (`true`/`false`).
  static bool get bulkInsertParallelEnabled {
    final raw = _optionalEnv('ODBC_BULK_INSERT_PARALLEL_ENABLED');
    if (raw == null || raw.isEmpty) {
      return defaultBulkInsertParallelEnabled;
    }
    final normalized = raw.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultBulkInsertParallelEnabled;
  }

  /// Row count above which direct bulk inserts may use `bulkInsertParallel`.
  ///
  /// Override with env `ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD` (positive integer).
  static int get bulkInsertParallelRowThreshold =>
      _positiveIntEnv('ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD') ?? defaultBulkInsertParallelRowThreshold;

  /// Parallel fan-out for `bulkInsertParallel`, aligned with read-only batch policy.
  static int bulkInsertParallelismForPoolSize(int poolSize) {
    return readOnlyBatchParallelismForPoolSize(poolSize);
  }

  /// When true, adaptive pool warm-up pre-creates native pool slots for
  /// eligible drivers (SQL Server, PostgreSQL).
  ///
  /// Override with env `ODBC_NATIVE_WARMUP_ENABLED` (`true`/`false`).
  static bool get nativeWarmUpEnabled {
    final raw = _optionalEnv('ODBC_NATIVE_WARMUP_ENABLED');
    if (raw == null || raw.isEmpty) {
      return defaultNativeWarmUpEnabled;
    }
    final normalized = raw.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultNativeWarmUpEnabled;
  }

  /// Homogeneous `INSERT` command count above which `sql.executeBatch` records a
  /// recommendation to migrate callers to `sql.bulkInsert`.
  static int get batchBulkInsertRecommendationThreshold =>
      _positiveIntEnv('ODBC_BATCH_BULK_INSERT_RECOMMEND_THRESHOLD') ?? defaultBatchBulkInsertRecommendationThreshold;

  /// Homogeneous `INSERT` command count above which the gateway may auto-route
  /// an `sql.executeBatch` workload to the native bulk-insert path.
  static int get batchBulkInsertRouteThreshold =>
      _positiveIntEnv('ODBC_BATCH_BULK_INSERT_ROUTE_THRESHOLD') ?? defaultBatchBulkInsertRouteThreshold;

  /// Safe parallel fan-out for homogeneous read-only ODBC / JSON-RPC batch work.
  ///
  /// Matches read-only ODBC batch parallelism (`poolSize ~/ 2`, minimum 1).
  static int readOnlyBatchParallelismForPoolSize(int poolSize) {
    final effectivePoolSize = poolSize > 0 ? poolSize : 1;
    return math.max(1, effectivePoolSize ~/ 2);
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

  /// Extra slack for the presentation-layer negotiating watchdog beyond transport
  /// register + re-register cycles.
  static const int capabilitiesNegotiationWatchdogMarginMs = 2000;

  /// UI backstop when hub status stays negotiating beyond transport capability
  /// timeout cycles (initial register + [capabilitiesMaxReRegisterAttempts] retries).
  static int get capabilitiesNegotiationWatchdogMs =>
      capabilitiesTimeoutMs * (capabilitiesMaxReRegisterAttempts + 1) + capabilitiesNegotiationWatchdogMarginMs;

  /// Socket.IO client internal reconnection attempts (transport-level).
  static const int socketReconnectionAttempts = 15;
  static const int socketReconnectionDelayMs = 5000;
  static const int socketReconnectionDelayMaxMs = 60000;

  static const Duration socketHeartbeatInterval = Duration(seconds: 20);
  static const Duration socketHeartbeatAckTimeout = Duration(seconds: 8);
  static const int socketMaxMissedHeartbeats = 2;

  static const int maxConnectionPools = 64;
  static const int maxBackpressureChunkQueueSize = 1000;

  /// Default max rows kept in Playground UI during ODBC streaming (memory / grid cost).
  static const int defaultPlaygroundStreamingMaxResultRows = 10000;

  /// Max rows kept in Playground UI during ODBC streaming (override via
  /// `PLAYGROUND_STREAMING_MAX_RESULT_ROWS`).
  static int get playgroundStreamingMaxResultRows =>
      _positiveIntEnv('PLAYGROUND_STREAMING_MAX_RESULT_ROWS') ?? defaultPlaygroundStreamingMaxResultRows;

  /// Max rows materialized in the Playground grid during streaming. Rows beyond
  /// this window are dropped from the front (sliding window) while
  /// [playgroundStreamingMaxResultRows] still bounds total fetched rows.
  ///
  /// Override with env `PLAYGROUND_STREAMING_UI_WINDOW_ROWS` (positive integer).
  static const int defaultPlaygroundStreamingUiWindowRows = 2000;

  static int get playgroundStreamingUiWindowRows {
    final configured = _positiveIntEnv('PLAYGROUND_STREAMING_UI_WINDOW_ROWS');
    if (configured == null) {
      return defaultPlaygroundStreamingUiWindowRows;
    }
    final cap = playgroundStreamingMaxResultRows;
    return configured > cap ? cap : configured;
  }

  /// Headroom above [rpcSqlExecuteConcurrencySoftLimit] for concurrent non-sql
  /// RPC handlers on the same socket (health, profile, batch, etc.).
  static const int defaultMaxConcurrentRpcHandlersHeadroom = 96;

  /// Max in-flight `rpc:request` handlers per socket connection (backpressure).
  ///
  /// Defaults to SQL queue soft limit plus [defaultMaxConcurrentRpcHandlersHeadroom].
  /// Override with env `MAX_CONCURRENT_RPC_HANDLERS`.
  static int get maxConcurrentRpcHandlers =>
      _positiveIntEnv('MAX_CONCURRENT_RPC_HANDLERS') ??
      rpcSqlExecuteConcurrencySoftLimit + defaultMaxConcurrentRpcHandlersHeadroom;

  /// Max simultaneously registered RPC streaming emitters per socket connection.
  /// Each emitter holds buffered chunks awaiting `rpc:stream.pull` from the hub;
  /// the cap protects memory if streams never receive a final pull/complete.
  static const int maxConcurrentRpcStreams = 640;

  /// Idle timeout for an RPC streaming emitter. If the hub does not call
  /// `rpc:stream.pull` within this window after the last activity, the emitter
  /// is unregistered defensively to avoid leaks across long-lived sockets.
  static const Duration rpcStreamEmitterMaxIdle = Duration(seconds: 300);

  /// Wall-clock interval for best-effort purge of expired rows in the persisted
  /// RPC idempotency cache (Drift). Independent of per-entry TTL applied when
  /// caching successful idempotent RPC responses.
  static const Duration rpcIdempotencyExpiredPurgeInterval = Duration(minutes: 15);

  /// TTL for each persisted RPC idempotency cache entry (SQLite `expires_at`).
  ///
  /// Override with env `RPC_IDEMPOTENCY_CACHE_TTL_SECONDS` (integer seconds).
  /// Clamped to 60..86400 (1 minute through 24 hours). Default 300 (5 minutes).
  static Duration get rpcIdempotencyEntryTtl {
    final parsed = int.tryParse(_optionalEnv('RPC_IDEMPOTENCY_CACHE_TTL_SECONDS') ?? '');
    final seconds = (parsed == null || parsed <= 0) ? 300 : parsed.clamp(60, 86400);
    return Duration(seconds: seconds);
  }

  /// TTL for cached successful responses of `agent.action.run` and
  /// `agent.action.validateRun` in [IIdempotencyStore] (Drift).
  ///
  /// Default: min([agentActionExecutionRetention], 24 h) so Hub retries after
  /// reconnect still hit the RPC cache while limiting SQLite growth. Dedup beyond
  /// this window uses persisted `agent_action_execution` rows (same
  /// `action_id` + `idempotency_key`) until execution history retention.
  ///
  /// Override with env `AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS` (60..259200).
  static Duration get agentActionRpcIdempotencyEntryTtl {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS') ?? '');
    if (parsed != null && parsed > 0) {
      return Duration(seconds: parsed.clamp(60, 259200));
    }
    final retentionSeconds = agentActionExecutionRetention.inSeconds;
    final defaultSeconds = retentionSeconds > 86400 ? 86400 : retentionSeconds;
    return Duration(seconds: defaultSeconds < 60 ? 60 : defaultSeconds);
  }

  /// Wall-clock interval for best-effort purge of old rows in the append-only
  /// `agent_action_remote_audit` table (Drift).
  static const Duration agentActionRemoteAuditPurgeInterval = Duration(minutes: 15);

  /// Retention window for `agent_action_remote_audit.occurred_at` (UTC).
  ///
  /// Override with env `AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS` (integer days).
  /// Clamped to 7..3650. Default 90.
  static Duration get agentActionRemoteAuditRetention {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS') ?? '');
    final days = (parsed == null || parsed <= 0) ? 90 : parsed.clamp(7, 3650);
    return Duration(days: days);
  }

  /// Wall-clock interval for best-effort purge of **terminal** rows in
  /// `agent_action_execution` older than [agentActionExecutionRetention].
  static const Duration agentActionExecutionPurgeInterval = Duration(minutes: 15);

  /// Retention window for persisted terminal `agent_action_execution` history.
  ///
  /// Override with env `AGENT_ACTION_EXECUTION_RETENTION_DAYS` (integer days).
  /// Clamped to 1..3650. Default 3.
  static Duration get agentActionExecutionRetention {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_EXECUTION_RETENTION_DAYS') ?? '');
    final days = (parsed == null || parsed <= 0) ? 3 : parsed.clamp(1, 3650);
    return Duration(days: days);
  }

  /// Wall-clock interval for clearing stored stdout/stderr on old terminal executions.
  static const Duration agentActionCapturedOutputPurgeInterval = Duration(minutes: 15);

  /// Retention for redacted stdout/stderr columns on terminal `agent_action_execution` rows.
  ///
  /// Shorter than [agentActionExecutionRetention]: metadata stays until history purge,
  /// captured blobs are cleared earlier to limit SQLite growth.
  ///
  /// Override with env `AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS` (1..720). Default 24.
  static Duration get agentActionCapturedOutputRetention {
    final parsed = int.tryParse(_optionalEnv('AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS') ?? '');
    final hours = (parsed == null || parsed <= 0) ? 24 : parsed.clamp(1, 720);
    final duration = Duration(hours: hours);
    final historyRetention = agentActionExecutionRetention;
    return duration > historyRetention ? historyRetention : duration;
  }

  /// Max distinct receive-pipeline entries cached per socket connection.
  /// Each entry is keyed by `(encoding, compression, schemaVersion, threshold)`.
  /// LRU eviction; raise this if `pipeline_cache_eviction` metrics show churn.
  static const int receivePipelineCacheMaxEntries = 16;

  /// Default max successful `client_token.getPolicy` calls per minute per agent+credential scope.
  /// Override with env `CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE` (`0` = unlimited).
  static const int clientTokenGetPolicyDefaultMaxPerMinute = 1200;

  /// Max distinct agent+credential scopes tracked by the getPolicy rate limiter at once.
  /// Override with env `CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS` (`0` = no cap on distinct keys).
  static const int clientTokenGetPolicyDefaultMaxScopeKeys = 8192;

  /// Minimum wall-clock interval between HTTP token refresh attempts during hub
  /// recovery (reduces auth endpoint load when the transport is still failing).
  static const Duration hubTokenRefreshMinInterval = Duration(seconds: 5);

  /// Refresh hub access JWT this long before JWT `exp` (server default ~4h).
  static const Duration hubAccessTokenProactiveRefreshMargin = Duration(minutes: 10);

  /// When hub reconnect logs omit user-facing error text (`recordErrorMessage: false`),
  /// emit a warning every N failures to avoid log storms during persistent retry.
  static const int hubReconnectFailureLogThrottleStride = 10;

  /// Log hub reachability probes that exceed this duration (diagnostics).
  static const int hubAvailabilityProbeSlowLogThresholdMs = 1000;

  /// UTF-8 JSON size above which message tracing replaces the raw payload with a
  /// summary (when `FeatureFlags.enableSocketSummarizeLargePayloadLogs` is on).
  static const int socketLogPayloadSummaryThresholdBytes = 8192;

  /// Inbound `rpc:request` payloads above this UTF-8 size skip JSON Schema
  /// validation to avoid O(payload) cost on already-size-limited messages.
  /// Requests this large already passed the negotiated payload limit check.
  static const int defaultSchemaValidationSkipAboveBytes = 128 * 1024;

  /// Effective inbound schema-validation skip threshold.
  ///
  /// Override with env `INBOUND_SCHEMA_VALIDATION_SKIP_ABOVE_BYTES` (positive
  /// integer bytes). `0` disables the soft cap (always validate).
  static int get schemaValidationSkipAboveBytes {
    final override = _positiveIntEnv('INBOUND_SCHEMA_VALIDATION_SKIP_ABOVE_BYTES');
    if (override != null) {
      return override;
    }
    return defaultSchemaValidationSkipAboveBytes;
  }

  /// Outgoing `rpc:response` contract validation is skipped above this UTF-8 JSON
  /// size to limit CPU on huge results (0 disables the soft cap).
  static const int socketOutgoingContractValidationMaxBytes = 2 * 1024 * 1024;

  /// Default payload size above which GZIP compress/decompress runs in a background isolate.
  ///
  /// Send path compares UTF-8 size before compression; receive path compares
  /// `originalSize` from frame metadata (decoded payload size), not wire bytes.
  /// Benchmark sweep (2026-05, async path, SQL + blob cases): 32 KiB matched or
  /// beat 16 KiB on p95 receive for large gzip payloads while avoiding extra isolate
  /// churn on sub-threshold frames; 64 KiB increased main-isolate gzip cost without
  /// clear win. Tune with `TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES` or
  /// `tool/benchmarks/benchmark_transport_pipeline.dart --gzip-isolate-threshold-sweep`.
  static const int defaultGzipIsolateThresholdBytes = 32 * 1024;

  /// JSON tree size above which `rpc:chunk` / `rpc:complete` encoding uses `compute`.
  ///
  /// Lower than `jsonPayloadIsolateEncodeThresholdBytes` so streaming row payloads
  /// do not block the UI isolate between ODBC fetches.
  static const int streamingChunkJsonIsolateThresholdBytes = 32 * 1024;

  /// Row count in an `rpc:chunk` payload above which JSON encoding always uses
  /// `compute`, even when the byte-size heuristic is below
  /// [streamingChunkJsonIsolateThresholdBytes].
  static const int streamingChunkRowIsolateThreshold = 50;

  /// Dedicated `rpc:chunk` JSON encode isolate threshold (lower than generic
  /// responses so frequent small chunks stay off the UI isolate).
  static const int defaultRpcChunkJsonIsolateThresholdBytes = 16 * 1024;

  static int get rpcChunkJsonIsolateThresholdBytes =>
      _positiveIntEnv('RPC_CHUNK_JSON_ISOLATE_THRESHOLD_BYTES') ?? defaultRpcChunkJsonIsolateThresholdBytes;

  /// Dedicated `rpc:chunk` gzip isolate threshold.
  static const int defaultRpcChunkGzipIsolateThresholdBytes = 16 * 1024;

  static int get rpcChunkGzipIsolateThresholdBytes =>
      _positiveIntEnv('RPC_CHUNK_GZIP_ISOLATE_THRESHOLD_BYTES') ?? defaultRpcChunkGzipIsolateThresholdBytes;

  /// GZIP compression threshold for `rpc:chunk` / `rpc:complete` only.
  static const int defaultRpcChunkCompressionThresholdBytes = 2048;

  static int get rpcChunkCompressionThresholdBytes =>
      _positiveIntEnv('RPC_CHUNK_COMPRESSION_THRESHOLD_BYTES') ?? defaultRpcChunkCompressionThresholdBytes;

  /// Row-count isolate threshold dedicated to `rpc:chunk` events.
  static const int defaultRpcChunkRowIsolateThreshold = 32;

  static int get rpcChunkRowIsolateThreshold =>
      _positiveIntEnv('RPC_CHUNK_ROW_ISOLATE_THRESHOLD') ?? defaultRpcChunkRowIsolateThreshold;

  /// When false (default), columnar `rpc:chunk` payloads skip gzip because they
  /// are typically low compressibility. Override with
  /// `RPC_CHUNK_COLUMNAR_GZIP_ENABLED` (`true`/`false`).
  static const bool defaultRpcChunkColumnarGzipEnabled = false;

  static bool get rpcChunkColumnarGzipEnabled {
    final raw = _optionalEnv('RPC_CHUNK_COLUMNAR_GZIP_ENABLED');
    if (raw == null || raw.isEmpty) {
      return defaultRpcChunkColumnarGzipEnabled;
    }
    final normalized = raw.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultRpcChunkColumnarGzipEnabled;
  }

  /// Sample rate for `rpc:chunk` protocol metrics (record 1 in N events).
  /// Override with `PROTOCOL_METRICS_RPC_CHUNK_SAMPLE_RATE` (integer >= 1).
  static const int defaultProtocolMetricsRpcChunkSampleRate = 10;

  static int get protocolMetricsRpcChunkSampleRate {
    final parsed = _positiveIntEnv('PROTOCOL_METRICS_RPC_CHUNK_SAMPLE_RATE');
    if (parsed == null || parsed < 1) {
      return defaultProtocolMetricsRpcChunkSampleRate;
    }
    return parsed;
  }

  /// TTL for in-memory authorization decision cache entries on the SQL hot path.
  ///
  /// Override with env `AUTH_DECISION_CACHE_TTL_SECONDS` (15..600). Default 60s.
  static const int defaultAuthorizationDecisionCacheTtlSeconds = 60;

  static Duration get authorizationDecisionCacheTtl {
    final parsed = int.tryParse(_optionalEnv('AUTH_DECISION_CACHE_TTL_SECONDS') ?? '');
    if (parsed != null && parsed > 0) {
      return Duration(seconds: parsed.clamp(15, 600));
    }
    return const Duration(seconds: defaultAuthorizationDecisionCacheTtlSeconds);
  }

  /// Returns true when SQL queue depth can exceed ODBC async pending slots.
  static bool isSqlQueueDepthAboveOdbcAsyncPending({
    required int sqlQueueMaxSize,
    required int asyncMaxPendingRequests,
  }) {
    return sqlQueueMaxSize > asyncMaxPendingRequests;
  }

  /// GZIP payload size above which transport compress/decompress uses `compute`.
  ///
  /// Override with env `TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES` (positive integer bytes).
  static int get gzipIsolateThresholdBytes =>
      _positiveIntEnv('TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES') ?? defaultGzipIsolateThresholdBytes;

  /// Transport-frame original size above which HMAC-SHA256 signing/verification
  /// is offloaded to a background isolate via `compute()`.
  ///
  /// HMAC is O(frame_size); for frames above this threshold the main-isolate
  /// signing cost is comparable to the gzip cost and worth offloading.
  /// Override with env `TRANSPORT_SIGNING_ISOLATE_THRESHOLD_BYTES`.
  static const int defaultSigningIsolateThresholdBytes = 64 * 1024;

  static int get signingIsolateThresholdBytes =>
      _positiveIntEnv('TRANSPORT_SIGNING_ISOLATE_THRESHOLD_BYTES') ?? defaultSigningIsolateThresholdBytes;

  /// Default credit advertised in
  /// `agent:capabilities.extensions.recommendedStreamPullWindowSize`.
  ///
  /// Raised from `1` to `12` so the hub starts with enough in-flight credits to
  /// keep streaming chunks moving without paying a round-trip per pull on LAN.
  /// The hub clamps this to its own ceiling and to `maxStreamPullWindowSize`
  /// (the agent advertises [maxBackpressureChunkQueueSize] as that ceiling).
  static const int defaultRecommendedStreamPullWindowSize = 12;

  /// Effective recommended pull window. Override with env
  /// `AGENT_STREAM_PULL_WINDOW_RECOMMENDED` (positive integer); clamped to
  /// `[1..maxBackpressureChunkQueueSize]`.
  static int get recommendedStreamPullWindowSize {
    final raw = _positiveIntEnv('AGENT_STREAM_PULL_WINDOW_RECOMMENDED') ?? defaultRecommendedStreamPullWindowSize;
    return raw.clamp(1, maxBackpressureChunkQueueSize);
  }

  /// Coalescing flush window for inbound `rpc:request_ack` debouncing. When a
  /// burst of `rpc:request` arrives (e.g. cross-agent `mergeAll`), individual
  /// acks are merged into a single `rpc:batch_ack` if more arrive before this
  /// timer elapses. See `plug_server/docs/plug_agente/03_performance_roadmap.md`
  /// item 3.
  static const Duration rpcAckCoalesceFlushInterval = Duration(milliseconds: 5);

  /// Maximum number of request ids coalesced into a single `rpc:batch_ack`.
  /// Mirrors the hub's `HUB_MAX_BATCH_SIZE` cap so the agent never produces a
  /// batch the hub cannot ingest in one frame.
  static const int rpcAckCoalesceMaxBatch = 32;

  /// When true, idle streaming ODBC connections may be cached briefly for the
  /// same connection string (SQL Server / PostgreSQL only).
  static bool get streamingConnectReuseEnabled {
    final raw = _optionalEnv('ODBC_STREAMING_CONNECT_REUSE_ENABLED');
    if (raw == null || raw.isEmpty) {
      return defaultStreamingConnectReuseEnabled;
    }
    final normalized = raw.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultStreamingConnectReuseEnabled;
  }

  /// TTL for cached idle streaming connections. Override with
  /// `ODBC_STREAMING_CONNECT_REUSE_TTL_SEC` (positive integer seconds).
  static Duration get streamingConnectReuseTtl {
    final parsed = int.tryParse(_optionalEnv('ODBC_STREAMING_CONNECT_REUSE_TTL_SEC') ?? '');
    final seconds = (parsed == null || parsed <= 0) ? defaultStreamingConnectReuseTtl.inSeconds : parsed;
    return Duration(seconds: seconds.clamp(5, 300));
  }

  /// Max distinct connection strings with a cached idle streaming connection.
  /// Override with `ODBC_STREAMING_CONNECT_REUSE_MAX_ENTRIES` (positive integer).
  static int get streamingConnectReuseMaxEntries {
    final parsed = _positiveIntEnv('ODBC_STREAMING_CONNECT_REUSE_MAX_ENTRIES');
    if (parsed == null) {
      return defaultStreamingConnectReuseMaxEntries;
    }
    return parsed.clamp(1, 64);
  }
}
