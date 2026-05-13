import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

final class OdbcGatewayConnectionManager {
  OdbcGatewayConnectionManager({
    required OdbcService service,
    required IConnectionPool connectionPool,
    required DirectOdbcConnectionLimiter directConnectionLimiter,
    required MetricsCollector metrics,
  }) : _service = service,
       _connectionPool = connectionPool,
       _directConnectionLimiter = directConnectionLimiter,
       _metrics = metrics;

  final OdbcService _service;
  final IConnectionPool _connectionPool;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final MetricsCollector _metrics;
  final Set<String> _connectionsToDiscard = <String>{};
  final Map<String, DateTime> _lastRecycleAttempt = <String, DateTime>{};

  Future<Result<String>> acquirePooledConnection(
    String connectionString, {
    ConnectionOptions? options,
    DateTime? deadline,
    Map<String, dynamic> context = const {},
  }) async {
    final acquireTimeout = _remainingTimeoutFromDeadline(deadline);
    if (acquireTimeout != null && acquireTimeout <= Duration.zero) {
      _metrics.recordPoolAcquireTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: 'pool_wait_timeout',
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
    required ConnectionOptions leaseFallbackOptions,
    DateTime? deadline,
    Map<String, dynamic> context = const {},
  }) async {
    final acquireTimeout = _remainingTimeoutFromDeadline(deadline);
    if (acquireTimeout != null && acquireTimeout <= Duration.zero) {
      _metrics.recordPoolAcquireTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: 'pool_wait_timeout',
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
    final acquireTimeout = _remainingTimeoutFromDeadline(deadline);
    if (acquireTimeout != null && acquireTimeout <= Duration.zero) {
      _metrics.recordDirectConnectionAcquireTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: 'direct_connection_limit_timeout',
      );
      return Failure(
        _poolBudgetExhaustedFailure(
          operation: 'direct_connection_acquire',
          context: {
            'direct_operation': operation,
            'reason': 'direct_connection_limit_timeout',
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
      unawaited(_discardConnectionSafely(connectionId));
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
        error is Exception ? error : Exception(error.toString()),
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

  Duration? _remainingTimeoutFromDeadline(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : remaining;
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
        'reason': context['reason'] ?? 'pool_wait_timeout',
        'retryable': true,
      },
    );
  }
}
