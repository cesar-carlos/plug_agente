import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/logging/odbc_resilience_log.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

final class OdbcGatewayConnectionManager implements IPoolDiscardInflightDiagnostics {
  OdbcGatewayConnectionManager({
    required OdbcService service,
    required IConnectionPool connectionPool,
    required DirectOdbcConnectionLimiter directConnectionLimiter,
    required MetricsCollector metrics,
    int Function()? directConnectionMaxProvider,
    Duration inflightDiscardStaleThreshold = const Duration(seconds: 30),
    int maxInflightPoolDiscards = 8,
  }) : _service = service,
       _connectionPool = connectionPool,
       _directConnectionLimiter = directConnectionLimiter,
       _metrics = metrics,
       _directConnectionMaxProvider = directConnectionMaxProvider,
       _inflightDiscardStaleThreshold = inflightDiscardStaleThreshold,
       _discardSemaphore = PoolSemaphore(maxInflightPoolDiscards);

  final OdbcService _service;
  final IConnectionPool _connectionPool;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final MetricsCollector _metrics;
  final int Function()? _directConnectionMaxProvider;
  final Duration _inflightDiscardStaleThreshold;
  final PoolSemaphore _discardSemaphore;
  final Map<String, PoolDiscardReason> _connectionsToDiscard = <String, PoolDiscardReason>{};
  final Map<String, Future<Result<void>>> _ownedDisconnects = {};
  final Map<String, DateTime> _lastRecycleAttempt = <String, DateTime>{};
  final Map<String, DateTime> _inflightDiscards = <String, DateTime>{};
  final Map<String, Future<Result<void>>> _discardTasks = {};

  @override
  int get poolDiscardInflightCount => _inflightDiscards.length;

  @override
  Future<void> reconcilePoolDiscardInflight() async {
    if (_inflightDiscards.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final staleIds = _inflightDiscards.entries
        .where((entry) => now.difference(entry.value) >= _inflightDiscardStaleThreshold)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (staleIds.isEmpty) {
      return;
    }

    _metrics.recordPoolDiscardReconciliationStale();
    developer.log(
      'Stale in-flight pooled connection discards detected during health reconciliation',
      name: 'database_gateway',
      level: 900,
      error: <String, Object?>{
        'stale_count': staleIds.length,
        'threshold_seconds': _inflightDiscardStaleThreshold.inSeconds,
      },
    );

    for (final connectionId in staleIds) {
      // The original native return still owns this handle. A second discard
      // or disconnect cannot confirm the outcome of that operation.
      markConnectionOutcomeUnknown(connectionId);
      _metrics.store.incrementEventCounter('odbc_cleanup_unconfirmed');
    }
  }

  Future<Result<String>> acquirePooledConnection(
    String connectionString, {
    ConnectionAcquireOptions? options,
    DateTime? deadline,
    Map<String, dynamic> context = const {},
  }) async {
    final acquireTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline);
    if (acquireTimeout != null && acquireTimeout <= Duration.zero) {
      _metrics.recordPoolAcquireTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: OdbcContextConstants.poolWaitTimeoutReason,
      );
      return Failure(
        _poolBudgetExhaustedFailure(
          operation: 'pool_acquire',
          context: context,
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final pool = _connectionPool;
      if (pool is ITimedConnectionPoolAcquire) {
        final timedPool = pool as ITimedConnectionPoolAcquire;
        return await timedPool.acquireWithin(
          connectionString,
          options: options,
          acquireTimeout: acquireTimeout,
        );
      }
      return await pool.acquire(connectionString, options: options);
    } finally {
      stopwatch.stop();
      _metrics.recordPoolWaitTime(stopwatch.elapsed);
    }
  }

  Future<Result<String>> acquireNativeCompatiblePooledConnection(
    String connectionString, {
    required ConnectionAcquireOptions leaseFallbackOptions,
    DateTime? deadline,
    Map<String, dynamic> context = const {},
  }) async {
    final acquireTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline);
    if (acquireTimeout != null && acquireTimeout <= Duration.zero) {
      _metrics.recordPoolAcquireTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: OdbcContextConstants.poolWaitTimeoutReason,
      );
      return Failure(
        _poolBudgetExhaustedFailure(
          operation: 'pool_acquire_native_compatible',
          context: context,
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final pool = _connectionPool;
      if (pool is INativeCompatibleConnectionPoolAcquire) {
        final nativeCompatiblePool = pool as INativeCompatibleConnectionPoolAcquire;
        return await nativeCompatiblePool.acquireNativeCompatible(
          connectionString,
          leaseFallbackOptions: leaseFallbackOptions,
          acquireTimeout: acquireTimeout,
        );
      }
      if (pool is ITimedConnectionPoolAcquire) {
        final timedPool = pool as ITimedConnectionPoolAcquire;
        return await timedPool.acquireWithin(
          connectionString,
          options: leaseFallbackOptions,
          acquireTimeout: acquireTimeout,
        );
      }
      return await pool.acquire(
        connectionString,
        options: leaseFallbackOptions,
      );
    } finally {
      stopwatch.stop();
      _metrics.recordPoolWaitTime(stopwatch.elapsed);
    }
  }

  Future<Result<DirectOdbcConnectionLease>> acquireDirectLease({
    required String operation,
    required DateTime? deadline,
  }) async {
    final maxConcurrent = _directConnectionMaxProvider?.call();
    if (maxConcurrent != null) {
      _directConnectionLimiter.reconfigureMaxConcurrent(maxConcurrent);
    }
    final acquireTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline);
    if (acquireTimeout != null && acquireTimeout <= Duration.zero) {
      _metrics.recordDirectConnectionAcquireTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: OdbcContextConstants.directConnectionLimitTimeoutReason,
      );
      return Failure(
        _poolBudgetExhaustedFailure(
          operation: 'direct_connection_acquire',
          context: {
            'direct_operation': operation,
            'reason': OdbcContextConstants.directConnectionLimitTimeoutReason,
            'retryable': true,
          },
        ),
      );
    }
    return _directConnectionLimiter.acquire(
      operation: operation,
      acquireTimeout: acquireTimeout,
    );
  }

  Future<Result<void>> disconnectOwnedConnectionSafely(
    String connectionId, {
    required String operation,
  }) async {
    if (_connectionsToDiscard[connectionId] == PoolDiscardReason.outcomeUnknown) {
      return Failure(
        domain.ConnectionFailure.withContext(
          message: 'Connection completion requires explicit recovery',
          context: const {'outcome_unknown': true, 'retryable': false},
        ),
      );
    }
    final work = _ownedDisconnects[connectionId] ??= _disconnectOwned(connectionId, operation);
    return work.timeout(
      ConnectionConstants.defaultPoolAcquireTimeout,
      onTimeout: () {
        markConnectionOutcomeUnknown(connectionId);
        return Failure(
          domain.ConnectionFailure.withContext(
            message: 'Connection cleanup was not confirmed',
            context: const {'outcome_unknown': true, 'retryable': false, 'timeout': true},
          ),
        );
      },
    );
  }

  Future<Result<void>> _disconnectOwned(String connectionId, String operation) async {
    try {
      final result = await _service.disconnect(connectionId);
      if (result.isSuccess()) {
        _connectionsToDiscard.remove(connectionId);
        return const Success(unit);
      }
      markConnectionOutcomeUnknown(connectionId);
      _metrics.recordPoolReleaseFailure();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          result.exceptionOrNull()!,
          operation: operation,
          context: const {'outcome_unknown': true, 'retryable': false},
        ),
      );
    } on Object catch (error) {
      markConnectionOutcomeUnknown(connectionId);
      _metrics.recordPoolReleaseFailure();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: operation,
          context: const {'outcome_unknown': true, 'retryable': false},
        ),
      );
    }
  }

  Future<Result<void>> disconnectOwnedConnectionAndReleaseLease({
    required String connectionId,
    required DirectOdbcConnectionLease directLease,
    required String operation,
  }) async {
    final observed = await disconnectOwnedConnectionSafely(connectionId, operation: operation);
    final work = _ownedDisconnects[connectionId];
    if (observed.isSuccess()) {
      directLease.release();
      _ownedDisconnects.remove(connectionId);
    } else if (work != null) {
      unawaited(
        work.then((result) {
          if (result.isSuccess()) {
            directLease.release();
            _ownedDisconnects.remove(connectionId);
          }
        }),
      );
    }
    return observed;
  }

  Future<void> releaseConnectionSafely(String connectionId) async {
    if (_discardTasks.containsKey(connectionId)) return;
    final discardReason = _connectionsToDiscard.remove(connectionId);
    if (discardReason != null) {
      final task = _runScheduledDiscard(connectionId, discardReason).whenComplete(() {
        _discardTasks.remove(connectionId);
      });
      _discardTasks[connectionId] = task;
      unawaited(task.then<void>((_) {}));
      return;
    }

    final releaseResult = await _connectionPool.release(connectionId);
    if (releaseResult.isSuccess()) {
      return;
    }

    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to release pooled connection (reason=pool_release_failed)',
      name: 'database_gateway',
      level: 900,
      error: const <String, Object?>{'operation': 'pool_release'},
    );
  }

  Future<Result<void>> _runScheduledDiscard(String connectionId, PoolDiscardReason reason) async {
    await _discardSemaphore.acquire();
    _inflightDiscards[connectionId] = DateTime.now();
    _metrics.recordPoolDiscardInflightStarted();
    try {
      return await _discardConnectionSafely(connectionId, reason);
    } finally {
      _clearInflightDiscard(connectionId);
      _discardSemaphore.release();
    }
  }

  /// Waits for confirmed cleanup; a timeout never releases an uncertain handle.
  Future<Result<void>> waitForPendingDiscards({required Duration timeout}) async {
    try {
      Future<Result<void>> drain() async {
        while (_discardTasks.isNotEmpty) {
          final results = await Future.wait(_discardTasks.values.toList(growable: false));
          for (final result in results) {
            if (result.isError()) return result;
          }
        }
        return const Success(unit);
      }

      final cleanup = await drain().timeout(timeout);
      if (cleanup.isError()) return cleanup;
      if (_connectionsToDiscard.isNotEmpty) {
        return Failure(
          domain.ConnectionFailure.withContext(
            message: 'Connection cleanup requires explicit recovery',
            context: {
              'cleanup_unconfirmed': true,
              'outcome_unknown': _connectionsToDiscard.values.contains(PoolDiscardReason.outcomeUnknown),
              'retryable': false,
            },
          ),
        );
      }
      return const Success(unit);
    } on TimeoutException catch (error) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'pool_wait_discard',
          context: const {'outcome_unknown': true, 'retryable': false},
        ),
      );
    }
  }

  void markConnectionForDiscard(
    String connectionId, {
    PoolDiscardReason reason = PoolDiscardReason.suspectConnection,
  }) {
    final current = _connectionsToDiscard[connectionId];
    if (current == PoolDiscardReason.poisonedPool || current == PoolDiscardReason.outcomeUnknown) {
      return;
    }
    _connectionsToDiscard[connectionId] = reason;
  }

  void markConnectionOutcomeUnknown(String connectionId) {
    _connectionsToDiscard[connectionId] = PoolDiscardReason.outcomeUnknown;
  }

  void recordPooledExecutionFailure({
    required String connectionString,
    required Object error,
    String? connectionId,
    String? stage,
  }) {
    final pool = _connectionPool;
    if (pool is IAdaptivePoolFeedback) {
      (pool as IAdaptivePoolFeedback).recordExecutionFailure(
        connectionString: connectionString,
        error: error,
        connectionId: connectionId,
        stage: stage,
      );
    }
  }

  Future<Result<Connection>> connectSafely(
    String connectionString, {
    required ConnectionOptions options,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await _service.connect(connectionString, options: options);
    } on Object catch (error) {
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'connect',
        ),
      );
    } finally {
      stopwatch.stop();
      _metrics.recordConnectTime(stopwatch.elapsed);
    }
  }

  Future<void> tryRecycleIdlePoolAfterConnectionLoss(
    String connectionString,
  ) async {
    final now = DateTime.now();
    final lastAttempt = _lastRecycleAttempt[connectionString];
    if (lastAttempt != null && now.difference(lastAttempt) < const Duration(seconds: 5)) {
      developer.log(
        'Skipping pool recycle: recent recycle attempt (<5s ago)',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    final activeCountResult = await _connectionPool.getActiveCount(
      connectionString: connectionString,
    );
    if (activeCountResult.isError()) {
      developer.log(
        'Skipping pool recycle because active-count snapshot failed',
        name: 'database_gateway',
        level: 900,
        error: const <String, Object?>{'reason': 'pool_active_count_unavailable'},
      );
      return;
    }

    final activeCount = activeCountResult.getOrThrow();
    if (activeCount > 0) {
      developer.log(
        'Skipping pool recycle because another lease for the same DSN is active',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    _lastRecycleAttempt[connectionString] = now;
    final recycleResult = await _connectionPool.recycle(connectionString);
    if (recycleResult.isSuccess()) {
      _metrics.recordPoolRecycle();
      OdbcResilienceLog.operational(
        event: 'pool_recycled',
        connectionString: connectionString,
      );
      return;
    }

    _metrics.recordPoolRecycleFailure();
    OdbcResilienceLog.warning(
      event: 'pool_recycle_failed',
      connectionString: connectionString,
      reason: 'pool_recycle_failed',
    );
  }

  void _clearInflightDiscard(String connectionId) {
    if (_inflightDiscards.remove(connectionId) != null) {
      _metrics.recordPoolDiscardInflightCompleted();
    }
  }

  Future<Result<void>> _discardConnectionSafely(
    String connectionId,
    PoolDiscardReason reason,
  ) async {
    Result<void> discardResult;
    try {
      discardResult = await _connectionPool.discard(connectionId, reason: reason);
    } on Object catch (error) {
      discardResult = Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'pool_discard',
          context: const {'outcome_unknown': true, 'retryable': false},
        ),
      );
    }
    if (discardResult.isSuccess()) {
      _connectionsToDiscard.remove(connectionId);
      return discardResult;
    }
    if (reason == PoolDiscardReason.outcomeUnknown ||
        OdbcErrorInspector.outcomeUnknown(discardResult.exceptionOrNull()!)) {
      _connectionsToDiscard[connectionId] = PoolDiscardReason.outcomeUnknown;
      _metrics.store.incrementEventCounter('odbc_cleanup_unconfirmed');
      return discardResult;
    }

    _connectionsToDiscard[connectionId] = reason;

    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to discard pooled connection (reason=pool_discard_failed)',
      name: 'database_gateway',
      level: 900,
      error: const <String, Object?>{'reason': 'pool_discard_failed'},
    );
    return discardResult;
  }

  domain.Failure _poolBudgetExhaustedFailure({
    required String operation,
    Map<String, dynamic> context = const {},
  }) {
    return OdbcFailureMapper.mapPoolError(
      TimeoutException('Pool acquire budget exhausted'),
      operation: operation,
      context: {
        ...context,
        'timeout': true,
        'timeout_stage': 'pool',
        'reason': context['reason'] ?? OdbcContextConstants.poolWaitTimeoutReason,
        'retryable': true,
      },
    );
  }
}
