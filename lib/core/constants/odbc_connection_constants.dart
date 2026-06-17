import 'dart:io' as io;
import 'dart:math' as math;

import 'package:plug_agente/core/constants/connection_constants_env.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';
/// ODBC pool, query, bulk-insert, and direct-connection limits.
abstract final class OdbcConnectionConstants {
  OdbcConnectionConstants._();

  static const Duration defaultLoginTimeout = Duration(seconds: 30);
  static const Duration defaultQueryTimeout = Duration(seconds: 60);
  static const Duration defaultTransactionalBatchTimeout = Duration(seconds: 60);
  static const Duration defaultStreamingQueryTimeout = Duration(minutes: 5);
  static const int defaultMaxResultBufferBytes = 64 * 1024 * 1024;
  static const int minMaxResultBufferMb = 8;
  static const int maxMaxResultBufferMb = 256;
  static const int maxAutoExpandedResultBufferBytes = maxMaxResultBufferMb * 1024 * 1024;
  static const int defaultSqlExecuteMaterializedMaxRows = 10000;
  static const int defaultSqlExecuteMaterializedMaxEstimatedBytes = 32 * 1024 * 1024;
  static const int defaultSqlExecuteMaterializedEstimatedBytesPerRow = 512;
  static const int defaultInitialResultBufferBytes = 256 * 1024;
  static const int defaultStreamingChunkSizeKb = 1024;
  static const Duration defaultStreamingConnectReuseTtl = Duration(seconds: 30);
  static const int defaultStreamingConnectReuseMaxEntries = 8;
  static const bool defaultStreamingConnectReuseEnabled = true;
  static const Duration defaultReconnectBackoff = Duration(seconds: 1);
  static const int defaultPoolSize = 8;
  static const Duration defaultPoolAcquireTimeout = Duration(seconds: 30);

  /// Max concurrent ODBC connection tests (UI/RPC probes bypass the SQL queue).
  static const int defaultMaxConcurrentConnectionTests = 2;

  static const Duration connectionTestAcquireTimeout = Duration(seconds: 10);
  static const Duration defaultNativePoolIdleTimeout = Duration(minutes: 5);
  static const Duration defaultNativePoolMaxLifetime = Duration(hours: 1);
  static const Duration defaultNativePoolConnectionTimeout = defaultPoolAcquireTimeout;

  /// ODBC pool size (configurable via ODBC_POOL_SIZE env var).
  static int get poolSize => ConnectionConstantsEnv.positiveInt('ODBC_POOL_SIZE') ?? defaultPoolSize;

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
    final override = ConnectionConstantsEnv.positiveInt('ODBC_ASYNC_WORKER_COUNT');
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

  static int? get directOdbcConnectionMaxConcurrentOverride =>
      ConnectionConstantsEnv.positiveInt('ODBC_DIRECT_CONNECTION_MAX_CONCURRENT');

  /// Hub `sql.execute` row cap above which materialized responses are rejected when
  /// streaming chunks are negotiated. Override with `SQL_EXECUTE_MATERIALIZED_MAX_ROWS`.
  static int get sqlExecuteMaterializedMaxRows =>
      ConnectionConstantsEnv.positiveInt('SQL_EXECUTE_MATERIALIZED_MAX_ROWS') ?? defaultSqlExecuteMaterializedMaxRows;

  /// Estimated byte budget for materialized `sql.execute` before forcing DB streaming
  /// or rejecting. Override with `SQL_EXECUTE_MATERIALIZED_MAX_BYTES`.
  static int get sqlExecuteMaterializedMaxEstimatedBytes =>
      ConnectionConstantsEnv.positiveInt('SQL_EXECUTE_MATERIALIZED_MAX_BYTES') ??
      defaultSqlExecuteMaterializedMaxEstimatedBytes;

  /// Rough bytes-per-row estimate used with [sqlExecuteMaterializedMaxEstimatedBytes].
  /// Override with `SQL_EXECUTE_MATERIALIZED_BYTES_PER_ROW`.
  static int get sqlExecuteMaterializedEstimatedBytesPerRow =>
      ConnectionConstantsEnv.positiveInt('SQL_EXECUTE_MATERIALIZED_BYTES_PER_ROW') ??
      defaultSqlExecuteMaterializedEstimatedBytesPerRow;

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
      ConnectionConstantsEnv.positiveInt('ODBC_BULK_INSERT_CHUNK_ROWS') ?? defaultBulkInsertChunkRowCount;

  /// When true, homogeneous read-only parallel batches may acquire worker
  /// connections through the native-compatible ODBC pool path.
  ///
  /// Override with env `ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED` (`true`/`false`).
  static bool get readOnlyBatchNativePoolEnabled {
    final raw = ConnectionConstantsEnv.optional('ODBC_READ_ONLY_BATCH_NATIVE_POOL_ENABLED');
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
    final raw = ConnectionConstantsEnv.optional('ODBC_BULK_INSERT_PARALLEL_ENABLED');
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
      ConnectionConstantsEnv.positiveInt('ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD') ??
      defaultBulkInsertParallelRowThreshold;

  /// Parallel fan-out for `bulkInsertParallel`, aligned with read-only batch policy.
  static int bulkInsertParallelismForPoolSize(int poolSize) {
    return readOnlyBatchParallelismForPoolSize(poolSize);
  }

  /// When true, adaptive pool warm-up pre-creates native pool slots for
  /// eligible drivers (SQL Server, PostgreSQL).
  ///
  /// Override with env `ODBC_NATIVE_WARMUP_ENABLED` (`true`/`false`).
  static bool get nativeWarmUpEnabled {
    final raw = ConnectionConstantsEnv.optional('ODBC_NATIVE_WARMUP_ENABLED');
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
      ConnectionConstantsEnv.positiveInt('ODBC_BATCH_BULK_INSERT_RECOMMEND_THRESHOLD') ??
      defaultBatchBulkInsertRecommendationThreshold;

  /// Homogeneous `INSERT` command count above which the gateway may auto-route
  /// an `sql.executeBatch` workload to the native bulk-insert path.
  static int get batchBulkInsertRouteThreshold =>
      ConnectionConstantsEnv.positiveInt('ODBC_BATCH_BULK_INSERT_ROUTE_THRESHOLD') ??
      defaultBatchBulkInsertRouteThreshold;

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

  /// Default max rows kept in Playground UI during ODBC streaming (memory / grid cost).
  static const int defaultPlaygroundStreamingMaxResultRows = 10000;

  /// Max rows kept in Playground UI during ODBC streaming (override via
  /// `PLAYGROUND_STREAMING_MAX_RESULT_ROWS`).
  static int get playgroundStreamingMaxResultRows =>
      ConnectionConstantsEnv.positiveInt('PLAYGROUND_STREAMING_MAX_RESULT_ROWS') ??
      defaultPlaygroundStreamingMaxResultRows;

  /// Max rows materialized in the Playground grid during streaming. Rows beyond
  /// this window are dropped from the front (sliding window) while
  /// [playgroundStreamingMaxResultRows] still bounds total fetched rows.
  ///
  /// Override with env `PLAYGROUND_STREAMING_UI_WINDOW_ROWS` (positive integer).
  static const int defaultPlaygroundStreamingUiWindowRows = 2000;

  static int get playgroundStreamingUiWindowRows {
    final configured = ConnectionConstantsEnv.positiveInt('PLAYGROUND_STREAMING_UI_WINDOW_ROWS');
    if (configured == null) {
      return defaultPlaygroundStreamingUiWindowRows;
    }
    final cap = playgroundStreamingMaxResultRows;
    return configured > cap ? cap : configured;
  }

  /// When true, idle streaming ODBC connections may be cached briefly for the
  /// same connection string (SQL Server / PostgreSQL only).
  static bool get streamingConnectReuseEnabled {
    final raw = ConnectionConstantsEnv.optional('ODBC_STREAMING_CONNECT_REUSE_ENABLED');
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
    final parsed = int.tryParse(ConnectionConstantsEnv.optional('ODBC_STREAMING_CONNECT_REUSE_TTL_SEC') ?? '');
    final seconds = (parsed == null || parsed <= 0) ? defaultStreamingConnectReuseTtl.inSeconds : parsed;
    return Duration(seconds: seconds.clamp(5, 300));
  }

  /// Max distinct connection strings with a cached idle streaming connection.
  /// Override with `ODBC_STREAMING_CONNECT_REUSE_MAX_ENTRIES` (positive integer).
  static int get streamingConnectReuseMaxEntries {
    final parsed = ConnectionConstantsEnv.positiveInt('ODBC_STREAMING_CONNECT_REUSE_MAX_ENTRIES');
    if (parsed == null) {
      return defaultStreamingConnectReuseMaxEntries;
    }
    return parsed.clamp(1, 64);
  }
}
