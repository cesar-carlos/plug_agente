import 'dart:async';

import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/repositories/i_direct_connection_limiter_diagnostics.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class DirectOdbcConnectionLimiter implements IDirectConnectionLimiterDiagnostics {
  DirectOdbcConnectionLimiter({
    required int maxConcurrent,
    required Duration acquireTimeout,
    MetricsCollector? metricsCollector,
  }) : _maxConcurrent = maxConcurrent,
       _semaphore = PoolSemaphore(maxConcurrent),
       _acquireTimeout = acquireTimeout,
       _metrics = metricsCollector;

  final int _maxConcurrent;
  final PoolSemaphore _semaphore;
  final Duration _acquireTimeout;
  final MetricsCollector? _metrics;
  int _activeCount = 0;
  int _openedTotal = 0;
  int _closedTotal = 0;

  @override
  int get activeCount => _activeCount;

  @override
  int get maxConcurrent => _maxConcurrent;

  @override
  int get openedTotal => _openedTotal;

  @override
  int get closedTotal => _closedTotal;

  @override
  bool get isSaturated => _activeCount >= _maxConcurrent;

  Future<Result<DirectOdbcConnectionLease>> acquire({
    required String operation,
    Duration? acquireTimeout,
  }) async {
    try {
      await _semaphore.acquire(timeout: acquireTimeout ?? _acquireTimeout);
    } on TimeoutException catch (error) {
      _metrics?.recordDirectConnectionAcquireTimeout();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError(
            'Direct ODBC connection limit exhausted while waiting for $operation: ${error.message}',
          ),
          operation: 'direct_connection_acquire',
          context: {
            'direct_operation': operation,
            'timeout': true,
            'timeout_stage': 'pool',
            'reason': 'direct_connection_limit_timeout',
            'retryable': true,
          },
        ),
      );
    }

    _activeCount++;
    _openedTotal++;
    _metrics?.recordDirectConnectionOpened();
    return Success(
      DirectOdbcConnectionLease._(
        onRelease: () {
          _semaphore.release();
          if (_activeCount > 0) {
            _activeCount--;
          }
          _closedTotal++;
          _metrics?.recordDirectConnectionClosed();
        },
      ),
    );
  }
}

class DirectOdbcConnectionLease {
  DirectOdbcConnectionLease._({required void Function() onRelease}) : _onRelease = onRelease;

  final void Function() _onRelease;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }

    _released = true;
    _onRelease();
  }
}
