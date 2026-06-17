import 'dart:math' as math;

import 'package:plug_agente/core/constants/connection_constants_env.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';
import 'package:plug_agente/core/constants/odbc_connection_constants.dart';

/// SQL execution queue, circuit breaker, and ODBC async pending coordination.
abstract final class SqlQueueConstants {
  SqlQueueConstants._();

  static const int defaultSqlQueueMaxSize = 16;

  /// SQL execution queue maximum size (configurable via SQL_QUEUE_MAX_SIZE env var).
  static int get sqlQueueMaxSize =>
      ConnectionConstantsEnv.positiveInt('SQL_QUEUE_MAX_SIZE') ?? defaultSqlQueueMaxSize;

  /// SQL execution queue maximum concurrent workers.
  ///
  /// Defaults to the persisted ODBC pool size used by the runtime dependency
  /// graph. `SQL_QUEUE_MAX_WORKERS` remains an explicit operational override.
  static int get sqlQueueMaxWorkers => sqlQueueMaxWorkersForPoolSize(OdbcConnectionConstants.poolSize);

  static int sqlQueueMaxWorkersForPoolSize(int persistedPoolSize) {
    return ConnectionConstantsEnv.positiveInt('SQL_QUEUE_MAX_WORKERS') ??
        (persistedPoolSize > 0 ? persistedPoolSize : OdbcConnectionConstants.defaultPoolSize);
  }

  /// Max pending requests accepted by the internal `odbc_fast` async pool.
  static int get odbcAsyncMaxPendingRequests =>
      odbcAsyncMaxPendingRequestsForPoolSize(OdbcConnectionConstants.poolSize);

  static int odbcAsyncMaxPendingRequestsForPoolSize(int poolSize) {
    final override = ConnectionConstantsEnv.positiveInt('ODBC_ASYNC_MAX_PENDING_REQUESTS');
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

  /// Soft in-flight `sql.execute` RPC limit per client token (or agent) scope.
  ///
  /// Matches SQL queue backpressure capacity: concurrent dispatch slots plus
  /// queue depth (`sqlQueueMaxWorkers + sqlQueueMaxSize`).
  static int get rpcSqlExecuteConcurrencySoftLimit => sqlQueueMaxWorkers + sqlQueueMaxSize;

  static int sqlQueueMaxBatchWorkersForWorkers(
    int maxWorkers, {
    int? persistedPoolSize,
  }) {
    return ConnectionConstantsEnv.positiveInt('SQL_QUEUE_MAX_BATCH_WORKERS') ??
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
    return ConnectionConstantsEnv.positiveInt('SQL_QUEUE_MAX_LONG_QUERY_WORKERS') ??
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
    return ConnectionConstantsEnv.positiveInt('SQL_QUEUE_MAX_STREAMING_WORKERS') ??
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
    return ConnectionConstantsEnv.positiveInt('SQL_QUEUE_MAX_NON_QUERY_WORKERS') ??
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
    final directGlobalBudget = OdbcConnectionConstants.directOdbcConnectionConcurrency(poolSize);
    final directClassCap = OdbcConnectionConstants.directOdbcOperationClassCap(operationClass, directGlobalBudget);
    return math.min(halfWorkers, directClassCap);
  }

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
    seconds: int.tryParse(ConnectionConstantsEnv.optional('SQL_QUEUE_TIMEOUT_SEC') ?? '') ?? 5,
  );

  /// Circuit breaker failure threshold (configurable via CIRCUIT_BREAKER_FAILURE_THRESHOLD env var).
  static int get circuitBreakerFailureThreshold =>
      int.tryParse(ConnectionConstantsEnv.optional('CIRCUIT_BREAKER_FAILURE_THRESHOLD') ?? '') ?? 5;

  /// Circuit breaker reset timeout in seconds (configurable via CIRCUIT_BREAKER_RESET_SEC env var).
  static Duration get circuitBreakerResetTimeout => Duration(
    seconds: int.tryParse(ConnectionConstantsEnv.optional('CIRCUIT_BREAKER_RESET_SEC') ?? '') ?? 30,
  );

  /// Returns true when SQL queue depth can exceed ODBC async pending slots.
  static bool isSqlQueueDepthAboveOdbcAsyncPending({
    required int sqlQueueMaxSize,
    required int asyncMaxPendingRequests,
  }) {
    return sqlQueueMaxSize > asyncMaxPendingRequests;
  }
}
