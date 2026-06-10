import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
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
  }) : _service = service,
       _connectionPool = connectionPool,
       _directConnectionLimiter = directConnectionLimiter,
       _metrics = metrics,
       _directConnectionMaxProvider = directConnectionMaxProvider,
       _inflightDiscardStaleThreshold = inflightDiscardStaleThreshold;

  final OdbcService _service;
  final IConnectionPool _connectionPool;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final MetricsCollector _metrics;
  final int Function()? _directConnectionMaxProvider;
  final Duration _inflightDiscardStaleThreshold;
  final Set<String> _connectionsToDiscard = <String>{};
  final Map<String, DateTime> _lastRecycleAttempt = <String, DateTime>{};
  final Map<String, DateTime> _inflightDiscards = <String, DateTime>{};

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
        'connection_ids': staleIds,
        'threshold_seconds': _inflightDiscardStaleThreshold.inSeconds,
      },
    );

    for (final connectionId in staleIds) {
      await _remediateStaleInflightDiscard(connectionId);
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

  Future<void> disconnectOwnedConnectionSafely(
    String connectionId, {
    required String operation,
  }) async {
    _connectionsToDiscard.remove(connectionId);
    late Result<void> disconnectResult;
    try {
      disconnectResult = await _service.disconnect(connectionId);
    } on Object catch (error) {
      disconnectResult = Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: operation,
        ),
      );
    }
    if (disconnectResult.isSuccess()) {
      return;
    }

    final disconnectError = disconnectResult.exceptionOrNull()!;
    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to disconnect owned ODBC connection: $connectionId ($operation)',
      name: 'database_gateway',
      level: 900,
      error: disconnectError,
    );
  }

  Future<void> disconnectOwnedConnectionAndReleaseLease({
    required String connectionId,
    required DirectOdbcConnectionLease directLease,
    required String operation,
  }) async {
    try {
      await disconnectOwnedConnectionSafely(
        connectionId,
        operation: operation,
      );
    } finally {
      directLease.release();
    }
  }

  Future<void> releaseConnectionSafely(String connectionId) async {
    final shouldDiscard = _connectionsToDiscard.remove(connectionId);
    if (shouldDiscard) {
      _inflightDiscards[connectionId] = DateTime.now();
      _metrics.recordPoolDiscardInflightStarted();
      unawaited(
        _discardConnectionSafely(connectionId).whenComplete(() {
          _inflightDiscards.remove(connectionId);
          _metrics.recordPoolDiscardInflightCompleted();
        }),
      );
      return;
    }

    final releaseResult = await _connectionPool.release(connectionId);
    if (releaseResult.isSuccess()) {
      return;
    }

    final releaseError = releaseResult.exceptionOrNull()!;
    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to release pooled connection: $connectionId',
      name: 'database_gateway',
      level: 900,
      error: releaseError,
    );
  }

  void markConnectionForDiscard(String connectionId) {
    _connectionsToDiscard.add(connectionId);
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

  Future<void> tryRecoverPoolAfterInvalidConnectionId(
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
        error: activeCountResult.exceptionOrNull(),
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
      developer.log(
        'Pool recycled after invalid connection id',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    _metrics.recordPoolRecycleFailure();
    developer.log(
      'Failed to recycle pool after invalid connection id',
      name: 'database_gateway',
      level: 900,
      error: recycleResult.exceptionOrNull(),
    );
  }

  Future<void> _remediateStaleInflightDiscard(String connectionId) async {
    final discardResult = await _connectionPool.discard(connectionId);
    if (discardResult.isSuccess()) {
      _clearInflightDiscard(connectionId);
      _metrics.recordPoolDiscardReconciliationRemediated();
      return;
    }

    final discardError = discardResult.exceptionOrNull()!;
    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Re-discard failed during stale in-flight reconciliation; forcing disconnect',
      name: 'database_gateway',
      level: 900,
      error: discardError,
    );

    await disconnectOwnedConnectionSafely(
      connectionId,
      operation: 'pool_discard_reconciliation_force_release',
    );
    _clearInflightDiscard(connectionId);
    _metrics.recordPoolDiscardReconciliationForceRelease();
  }

  void _clearInflightDiscard(String connectionId) {
    if (_inflightDiscards.remove(connectionId) != null) {
      _metrics.recordPoolDiscardInflightCompleted();
    }
  }

  Future<void> _discardConnectionSafely(String connectionId) async {
    final discardResult = await _connectionPool.discard(connectionId);
    if (discardResult.isSuccess()) {
      return;
    }

    final discardError = discardResult.exceptionOrNull()!;
    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to discard pooled connection: $connectionId',
      name: 'database_gateway',
      level: 900,
      error: discardError,
    );
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
