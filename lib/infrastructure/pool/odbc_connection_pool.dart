import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';

/// Aluga uma conexão ODBC por consulta via [OdbcService.connect] com
/// [ConnectionOptions] completos (buffer alinhado às configurações do app).
///
/// Evita falha `Buffer too small` em `poolReleaseConnection` do pool nativo
/// do `odbc_fast`, que não associa `maxResultBufferBytes` a conexões alugadas
/// do pool (caindo em buffer pequeno no worker).
class OdbcConnectionPool
    implements IConnectionPool, ITimedConnectionPoolAcquire, IConnectionPoolDiagnostics, IConnectionPoolWarmUp {
  OdbcConnectionPool(
    this._service,
    this._settings, {
    Duration? acquireTimeout,
    MetricsCollector? metricsCollector,
  }) : _semaphore = PoolSemaphore(_settings.poolSize),
       _nativeHandshakeSemaphore = PoolSemaphore(
         ConnectionConstants.leasePoolNativeHandshakeConcurrency(_settings.poolSize),
       ),
       _acquireTimeout = acquireTimeout ?? ConnectionConstants.defaultPoolAcquireTimeout,
       _metrics = metricsCollector;
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final PoolSemaphore _semaphore;
  final PoolSemaphore _nativeHandshakeSemaphore;
  final Duration _acquireTimeout;
  final MetricsCollector? _metrics;

  final Map<String, Set<String>> _leasedIdsByConnectionString = {};
  final Set<String> _leasedIds = {};

  bool _messageIndicatesInvalidConnectionId(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  bool _shouldForceFinalizeLeaseOnDisconnectError(Object error) {
    return _messageIndicatesInvalidConnectionId(error) || OdbcErrorInspector.isTimeout(error);
  }

  @override
  Future<Result<String>> acquire(
    String connectionString, {
    ConnectionOptions? options,
  }) {
    return acquireWithin(connectionString, options: options);
  }

  @override
  Future<Result<String>> acquireWithin(
    String connectionString, {
    ConnectionOptions? options,
    Duration? acquireTimeout,
  }) async {
    final effectiveAcquireTimeout = acquireTimeout ?? _acquireTimeout;
    try {
      await _semaphore.acquire(
        timeout: effectiveAcquireTimeout,
      );
    } on TimeoutException catch (error) {
      _metrics?.recordPoolAcquireTimeout();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError(
            'Pool exhausted while waiting for an available connection: '
            '${error.message}',
          ),
          operation: 'pool_acquire',
          context: {
            'timeout': true,
            'timeout_stage': 'pool',
            'reason': 'pool_wait_timeout',
            'retryable': true,
          },
        ),
      );
    }

    try {
      await _nativeHandshakeSemaphore.acquire(timeout: effectiveAcquireTimeout);
    } on TimeoutException catch (error) {
      _semaphore.release();
      _metrics?.recordPoolAcquireTimeout();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError(
            'ODBC worker busy (connect): ${error.message}',
          ),
          operation: 'pool_acquire',
          context: {
            'timeout': true,
            'timeout_stage': 'pool',
            'reason': 'odbc_worker_busy_connect',
            'retryable': true,
          },
        ),
      );
    }

    final resolvedOptions = options ?? OdbcConnectionOptionsBuilder.forQueryExecution(_settings);
    late Result<Connection> connectResult;
    try {
      try {
        final connectStopwatch = Stopwatch()..start();
        try {
          connectResult = await _service.connect(
            connectionString,
            options: resolvedOptions,
          );
        } finally {
          connectStopwatch.stop();
          _metrics?.recordConnectTime(connectStopwatch.elapsed);
        }
      } on Object catch (error) {
        _semaphore.release();
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'pool_acquire',
          ),
        );
      }
    } finally {
      _nativeHandshakeSemaphore.release();
    }

    return connectResult.fold(
      (Connection connection) {
        _leasedIdsByConnectionString.putIfAbsent(connectionString, () => <String>{}).add(connection.id);
        _leasedIds.add(connection.id);
        developer.log(
          'Acquired ODBC connection ${connection.id} (lease)',
          name: 'connection_pool',
          level: 500,
        );
        return Success(connection.id);
      },
      (error) {
        _semaphore.release();
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'pool_acquire',
          ),
        );
      },
    );
  }

  @override
  Future<Result<void>> release(String connectionId) async {
    return _disconnectLeasedConnection(
      connectionId,
      operation: 'pool_release',
      logMessage: 'Failed to disconnect leased ODBC connection $connectionId',
      releaseLeaseOnFailure: false,
      eagerLeaseRelease: false,
    );
  }

  @override
  Future<Result<void>> discard(String connectionId) async {
    return _disconnectLeasedConnection(
      connectionId,
      operation: 'pool_discard',
      logMessage: 'Failed to discard leased ODBC connection $connectionId',
      releaseLeaseOnFailure: true,
      eagerLeaseRelease: true,
    );
  }

  @override
  Future<Result<void>> closeAll() async {
    developer.log(
      'Disconnecting all leased ODBC connections',
      name: 'connection_pool',
      level: 500,
    );

    final errors = <String>[];
    final ids = _leasedIds.toList(growable: false);
    for (final id in ids) {
      final result = await release(id);
      if (result.isError()) {
        final err = result.exceptionOrNull();
        errors.add(err?.toString() ?? 'release failed');
      }
    }

    if (errors.isNotEmpty) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          Exception(errors.join(', ')),
          operation: 'pool_close_all',
        ),
      );
    }
    return const Success(unit);
  }

  /// Pre-warms the pool with connections to reduce first-request latency.
  ///
  /// Acquires [warmUpCount] connections (default: half of pool size), then
  /// releases them immediately. This ensures connections are ready and reduces
  /// cold-start latency.
  ///
  /// Returns aggregated failures when cleanup or acquisition cannot complete.
  @override
  Future<Result<void>> warmUp(
    String connectionString, {
    int? warmUpCount,
  }) async {
    final count = warmUpCount ?? (_settings.poolSize / 2).ceil();
    final connectionIds = <String>[];
    final errors = <String>[];

    developer.log(
      'Warming up connection pool with $count connections',
      name: 'connection_pool',
      level: 800,
    );

    try {
      for (var i = 0; i < count; i++) {
        final result = await acquire(connectionString);
        result.fold(
          connectionIds.add,
          (error) {
            developer.log(
              'Warm-up connection ${i + 1}/$count failed',
              name: 'connection_pool',
              level: 900,
              error: error,
            );
            errors.add('warmup_acquire_${i + 1}: $error');
          },
        );
      }

      developer.log(
        'Pool warm-up completed: ${connectionIds.length}/$count connections',
        name: 'connection_pool',
        level: 800,
      );
    } finally {
      for (final id in connectionIds) {
        final cleanup = await discard(id);
        cleanup.fold(
          (_) {},
          (error) {
            developer.log(
              'Warm-up cleanup failed for $id',
              name: 'connection_pool',
              level: 900,
              error: error,
            );
            errors.add('warmup_cleanup_$id: $error');
          },
        );
      }
    }

    if (errors.isNotEmpty) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError(errors.join(', ')),
          operation: 'pool_warm_up',
        ),
      );
    }

    return const Success(unit);
  }

  @override
  Future<Result<void>> recycle(String connectionString) async {
    final ids = _leasedIdsByConnectionString[connectionString]?.toList(
      growable: false,
    );
    if (ids == null || ids.isEmpty) {
      return const Success(unit);
    }

    developer.log(
      'Recycling leased ODBC connections for connection string',
      name: 'connection_pool',
      level: 800,
    );

    final errors = <String>[];
    for (final id in ids) {
      final result = await release(id);
      if (result.isError()) {
        final error = result.exceptionOrNull();
        errors.add(error?.toString() ?? 'release failed');
      }
    }

    if (errors.isNotEmpty) {
      _metrics?.recordPoolRecycleFailure();
      return Failure(
        OdbcFailureMapper.mapPoolError(
          Exception(errors.join(', ')),
          operation: 'pool_recycle',
        ),
      );
    }
    return const Success(unit);
  }

  @override
  Future<Result<int>> getActiveCount({String? connectionString}) async {
    if (connectionString == null) {
      return Success(_leasedIds.length);
    }

    return Success(
      _leasedIdsByConnectionString[connectionString]?.length ?? 0,
    );
  }

  @override
  Future<Result<void>> healthCheckAll() async {
    return const Success(unit);
  }

  Future<Result<void>> _disconnectLeasedConnection(
    String connectionId, {
    required String operation,
    required String logMessage,
    required bool releaseLeaseOnFailure,
    required bool eagerLeaseRelease,
  }) async {
    final hadLease = _leasedIds.contains(connectionId);
    var leaseReleasedEarly = false;

    if (eagerLeaseRelease) {
      _finalizeLeaseRelease(connectionId, hadLease: hadLease);
      leaseReleasedEarly = true;
    }

    var handshakeHeld = false;
    if (!eagerLeaseRelease) {
      try {
        await _nativeHandshakeSemaphore.acquire(timeout: _acquireTimeout);
        handshakeHeld = true;
      } on TimeoutException catch (error) {
        developer.log(
          'ODBC native handshake slot timeout during release; disconnecting anyway',
          name: 'connection_pool',
          level: 900,
          error: error,
        );
      }
    }

    late Result<void> disconnectResult;
    try {
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
    } finally {
      if (handshakeHeld) {
        _nativeHandshakeSemaphore.release();
      }
    }

    return disconnectResult.fold(
      (_) {
        if (!leaseReleasedEarly) {
          _finalizeLeaseRelease(connectionId, hadLease: hadLease);
        }
        return const Success(unit);
      },
      (error) {
        if (_messageIndicatesInvalidConnectionId(error)) {
          if (!leaseReleasedEarly) {
            _finalizeLeaseRelease(connectionId, hadLease: hadLease);
          }
          return const Success(unit);
        }

        _metrics?.recordPoolReleaseFailure();
        developer.log(
          logMessage,
          name: 'connection_pool',
          level: 900,
          error: error,
        );

        if (!leaseReleasedEarly && (releaseLeaseOnFailure || _shouldForceFinalizeLeaseOnDisconnectError(error))) {
          _finalizeLeaseRelease(connectionId, hadLease: hadLease);
        }

        return Failure(
          OdbcFailureMapper.mapPoolError(
            error,
            operation: operation,
          ),
        );
      },
    );
  }

  void _finalizeLeaseRelease(
    String connectionId, {
    required bool hadLease,
  }) {
    final removed = _removeLeaseTracking(connectionId);
    if (hadLease && removed) {
      _semaphore.release();
    }
  }

  bool _removeLeaseTracking(String connectionId) {
    final removed = _leasedIds.remove(connectionId);
    if (!removed) {
      return false;
    }

    for (final entry in _leasedIdsByConnectionString.entries) {
      entry.value.remove(connectionId);
    }
    _leasedIdsByConnectionString.removeWhere((_, ids) => ids.isEmpty);
    return true;
  }

  @override
  Map<String, Object?> getHealthDiagnostics() {
    return const {
      'strategy': 'lease',
      'native_pool_exposed': false,
    };
  }
}
