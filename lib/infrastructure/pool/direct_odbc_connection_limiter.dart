import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
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
  }) : _globalSemaphore = PoolSemaphore(maxConcurrent),
       _acquireTimeout = acquireTimeout,
       _metrics = metricsCollector,
       _classSemaphores = {
         for (final operationClass in DirectOdbcOperationClass.values)
           operationClass: PoolSemaphore(
             ConnectionConstants.directOdbcOperationClassCap(operationClass, maxConcurrent),
           ),
       },
       _classActiveCounts = {
         for (final operationClass in DirectOdbcOperationClass.values) operationClass: 0,
       };

  final PoolSemaphore _globalSemaphore;
  final Map<DirectOdbcOperationClass, PoolSemaphore> _classSemaphores;
  final Map<DirectOdbcOperationClass, int> _classActiveCounts;
  final Duration _acquireTimeout;
  final MetricsCollector? _metrics;
  int _activeCount = 0;
  int _openedTotal = 0;
  int _closedTotal = 0;

  @override
  int get activeCount => _activeCount;

  @override
  int get maxConcurrent => _globalSemaphore.maxConcurrent;

  @override
  int get openedTotal => _openedTotal;

  @override
  int get closedTotal => _closedTotal;

  @override
  bool get isSaturated => _activeCount >= maxConcurrent;

  bool isClassSaturated(DirectOdbcOperationClass operationClass) {
    final active = _classActiveCounts[operationClass] ?? 0;
    final cap = _classSemaphores[operationClass]!.maxConcurrent;
    return active >= cap;
  }

  @override
  Map<String, Object?> getOperationClassDiagnostics() {
    return {
      for (final operationClass in DirectOdbcOperationClass.values)
        operationClass.healthKey: <String, Object?>{
          'active_count': _classActiveCounts[operationClass] ?? 0,
          'max_concurrent': _classSemaphores[operationClass]!.maxConcurrent,
          'is_saturated': isClassSaturated(operationClass),
        },
    };
  }

  void reconfigureMaxConcurrent(int maxConcurrent) {
    if (maxConcurrent == _globalSemaphore.maxConcurrent) {
      return;
    }
    _globalSemaphore.resize(maxConcurrent);
    for (final operationClass in DirectOdbcOperationClass.values) {
      _classSemaphores[operationClass]!.resize(
        ConnectionConstants.directOdbcOperationClassCap(operationClass, maxConcurrent),
      );
    }
  }

  Future<Result<DirectOdbcConnectionLease>> acquire({
    required String operation,
    Duration? acquireTimeout,
  }) async {
    final operationClass = DirectOdbcOperationClass.fromOperation(operation);
    final classSemaphore = _classSemaphores[operationClass]!;
    final effectiveTimeout = acquireTimeout ?? _acquireTimeout;
    final stopwatch = Stopwatch()..start();
    var classSlotHeld = false;
    try {
      try {
        await classSemaphore.acquire(timeout: effectiveTimeout);
        classSlotHeld = true;
        await _globalSemaphore.acquire(timeout: effectiveTimeout);
      } on TimeoutException catch (error) {
        if (classSlotHeld) {
          classSemaphore.release();
        }
        _metrics?.recordDirectConnectionAcquireTimeout();
        return Failure(
          OdbcFailureMapper.mapPoolError(
            StateError(
              'Direct ODBC connection limit exhausted while waiting for $operation: ${error.message}',
            ),
            operation: 'direct_connection_acquire',
            context: {
              'direct_operation': operation,
              'direct_operation_class': operationClass.healthKey,
              'timeout': true,
              'timeout_stage': 'pool',
              'reason': OdbcContextConstants.directConnectionLimitTimeoutReason,
              'retryable': true,
            },
          ),
        );
      }
    } finally {
      stopwatch.stop();
      _metrics?.recordDirectConnectionWaitTime(stopwatch.elapsed);
    }

    _activeCount++;
    _classActiveCounts[operationClass] = (_classActiveCounts[operationClass] ?? 0) + 1;
    _openedTotal++;
    _metrics?.recordDirectConnectionOpened();
    return Success(
      DirectOdbcConnectionLease._(
        onRelease: () {
          _globalSemaphore.release();
          classSemaphore.release();
          if (_activeCount > 0) {
            _activeCount--;
          }
          final classActive = _classActiveCounts[operationClass] ?? 0;
          if (classActive > 0) {
            _classActiveCounts[operationClass] = classActive - 1;
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
