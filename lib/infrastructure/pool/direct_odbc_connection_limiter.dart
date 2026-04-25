import 'dart:async';

import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class DirectOdbcConnectionLimiter {
  DirectOdbcConnectionLimiter({
    required int maxConcurrent,
    required Duration acquireTimeout,
    MetricsCollector? metricsCollector,
  }) : _semaphore = PoolSemaphore(maxConcurrent),
       _acquireTimeout = acquireTimeout,
       _metrics = metricsCollector;

  final PoolSemaphore _semaphore;
  final Duration _acquireTimeout;
  final MetricsCollector? _metrics;

  Future<Result<DirectOdbcConnectionLease>> acquire({
    required String operation,
  }) async {
    try {
      await _semaphore.acquire(timeout: _acquireTimeout);
    } on TimeoutException catch (error) {
      _metrics?.recordDirectConnectionAcquireTimeout();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError(
            'Direct ODBC connection limit exhausted while waiting for $operation: ${error.message}',
          ),
          operation: 'direct_connection_acquire',
          context: {'direct_operation': operation},
        ),
      );
    }

    _metrics?.recordDirectConnectionOpened();
    return Success(
      DirectOdbcConnectionLease._(
        onRelease: () {
          _semaphore.release();
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
