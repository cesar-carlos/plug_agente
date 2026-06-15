import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_native_bulk_insert_pool.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Pool ODBC usando pool nativo do `odbc_fast` (conexões do pool não recebem
/// `ConnectionOptions` no repositório e podem cair em buffer ~512 KiB no
/// worker). Mantido para testes; o app usa lease em `odbc_connection_pool.dart`.
class OdbcNativeConnectionPool
    implements
        IConnectionPool,
        ITimedConnectionPoolAcquire,
        IConnectionPoolDiagnostics,
        IConnectionPoolWarmUp,
        IOdbcNativeBulkInsertPool {
  OdbcNativeConnectionPool(
    this._service,
    this._settings, {
    MetricsCollector? metricsCollector,
    OdbcProfileRecommendedOptions? recommendedOptions,
  }) : _metrics = metricsCollector,
       _recommendedOptions = recommendedOptions,
       _nativeHandshakeSemaphore = PoolSemaphore(
         ConnectionConstants.leasePoolNativeHandshakeConcurrency(_settings.poolSize),
       );
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final OdbcProfileRecommendedOptions? _recommendedOptions;
  final MetricsCollector? _metrics;
  final PoolSemaphore _nativeHandshakeSemaphore;

  final Map<String, int> _pools = {};
  final Map<String, Future<Result<int>>> _poolCreationFutures = {};
  int _activeAcquireCount = 0;

  String _odbcErrorMessage(Object error) => OdbcErrorInspector.message(error);

  bool _messageIndicatesInvalidConnectionId(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  String _poolConnectionString(String connectionString) {
    if (connectionString.toLowerCase().contains('pooltestoncheckout=')) {
      return connectionString;
    }

    final testOnCheckout = _settings.nativePoolTestOnCheckout;
    return '$connectionString;PoolTestOnCheckout=$testOnCheckout';
  }

  PoolOptions get _poolOptions {
    const plugDefaults = PoolOptions(
      idleTimeout: ConnectionConstants.defaultNativePoolIdleTimeout,
      maxLifetime: ConnectionConstants.defaultNativePoolMaxLifetime,
      connectionTimeout: ConnectionConstants.defaultNativePoolConnectionTimeout,
    );
    final recommended = _recommendedOptions?.pool;
    if (recommended == null) {
      return plugDefaults;
    }
    return OdbcRecommendedOptionsMerger.mergePoolOptions(
      recommended: recommended,
      plugOverrides: plugDefaults,
    );
  }

  @override
  Future<Result<int>> ensurePoolId(String connectionString) {
    return _getOrCreatePool(connectionString);
  }

  Future<Result<int>> _getOrCreatePool(String connectionString) async {
    final existingPoolId = _pools[connectionString];
    if (existingPoolId != null) {
      return Success(existingPoolId);
    }

    if (_pools.length >= ConnectionConstants.maxConnectionPools) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          Exception(
            'Connection pool limit reached (${ConnectionConstants.maxConnectionPools}). '
            'Recycle unused pools or reduce unique connection strings.',
          ),
          operation: 'pool_acquire',
        ),
      );
    }

    final inFlightCreation = _poolCreationFutures[connectionString];
    if (inFlightCreation != null) {
      return inFlightCreation;
    }

    final creationFuture = _createPool(connectionString);
    _poolCreationFutures[connectionString] = creationFuture;
    final result = await creationFuture;
    _poolCreationFutures.remove(connectionString);

    // If recycle() ran while creation was in-flight, _pools no longer contains
    // this connection string even though _createPool registered the new pool.
    // Close the orphaned pool immediately to avoid a resource leak.
    if (result.isSuccess() && !_pools.containsKey(connectionString)) {
      final orphanId = result.getOrThrow();
      developer.log(
        'Closing orphaned native pool $orphanId: recycle ran during creation',
        name: 'connection_pool',
        level: 900,
      );
      await _service.poolClose(orphanId);
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError('Pool was recycled during creation; retry to get a fresh pool.'),
          operation: 'pool_acquire',
          context: {'reason': OdbcContextConstants.poolNotCreatedReason, 'retryable': true},
        ),
      );
    }

    return result;
  }

  Future<Result<Map<String, Object?>>> getDetailedState(
    String connectionString,
  ) async {
    final poolId = _pools[connectionString];
    if (poolId == null) {
      return const Success(<String, Object?>{
        'available': false,
        'reason': OdbcContextConstants.poolNotCreatedReason,
      });
    }

    final stateResult = await _service.poolGetStateDetailed(poolId);
    return stateResult.fold(
      (state) => Success(<String, Object?>{
        'available': true,
        'pool_id': poolId,
        ...state,
      }),
      Failure.new,
    );
  }

  Future<Result<int>> _createPool(String connectionString) async {
    developer.log(
      'Creating native pool for connection',
      name: 'connection_pool',
      level: 500,
    );

    try {
      await _nativeHandshakeSemaphore.acquire(
        timeout: ConnectionConstants.defaultPoolAcquireTimeout,
      );
    } on TimeoutException catch (error) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError('ODBC worker busy (native pool_create): ${error.message}'),
          operation: 'pool_create',
        ),
      );
    }

    late Result<int> poolResult;
    try {
      poolResult = await _service.poolCreate(
        _poolConnectionString(connectionString),
        _settings.poolSize,
        options: _poolOptions,
      );
    } finally {
      _nativeHandshakeSemaphore.release();
    }

    return poolResult.fold(
      (poolId) {
        _pools[connectionString] = poolId;
        developer.log(
          'Native pool created: $poolId',
          name: 'connection_pool',
          level: 500,
        );
        return Success(poolId);
      },
      (error) {
        developer.log(
          'Failed to create pool',
          name: 'connection_pool',
          level: 1000,
          error: error,
        );
        return Failure(
          OdbcFailureMapper.mapPoolError(
            error,
            operation: 'pool_create',
          ),
        );
      },
    );
  }

  @override
  Future<Result<String>> acquire(
    String connectionString, {
    ConnectionAcquireOptions? options,
  }) {
    return acquireWithin(connectionString, options: options);
  }

  @override
  Future<Result<String>> acquireWithin(
    String connectionString, {
    ConnectionAcquireOptions? options,
    Duration? acquireTimeout,
  }) async {
    if (options != null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Native ODBC pool does not support custom connection options.',
          context: <String, dynamic>{
            'operation': 'pool_acquire',
            'reason': OdbcContextConstants.nativePoolCustomOptionsUnsupportedReason,
          },
        ),
      );
    }

    final poolResult = await _getOrCreatePool(connectionString);

    return poolResult.fold(
      (poolId) async {
        try {
          await _nativeHandshakeSemaphore.acquire(
            timeout: acquireTimeout ?? ConnectionConstants.defaultPoolAcquireTimeout,
          );
        } on TimeoutException catch (error) {
          return Failure(
            OdbcFailureMapper.mapPoolError(
              StateError(
                'ODBC worker busy (native pool_get_connection): ${error.message}',
              ),
              operation: 'pool_acquire',
              context: {
                'timeout': true,
                'timeout_stage': 'pool',
                'reason': OdbcContextConstants.odbcWorkerBusyConnectReason,
                'retryable': true,
              },
            ),
          );
        }

        late Result<Connection> connResult;
        try {
          connResult = await _service.poolGetConnection(poolId);
        } finally {
          _nativeHandshakeSemaphore.release();
        }

        return connResult.fold(
          (connection) {
            _activeAcquireCount++;
            return Success(connection.id);
          },
          (error) => Failure(
            OdbcFailureMapper.mapPoolError(
              error,
              operation: 'pool_acquire',
            ),
          ),
        );
      },
      Failure.new,
    );
  }

  @override
  Future<Result<void>> release(String connectionId) async {
    var handshakeHeld = false;
    try {
      await _nativeHandshakeSemaphore.acquire(
        timeout: ConnectionConstants.defaultPoolAcquireTimeout,
      );
      handshakeHeld = true;
    } on TimeoutException {
      developer.log(
        'Native pool release: handshake timeout; poolReleaseConnection anyway',
        name: 'connection_pool',
        level: 900,
      );
    }

    late Result<void> result;
    try {
      result = await _service.poolReleaseConnection(connectionId);
    } finally {
      if (handshakeHeld) {
        _nativeHandshakeSemaphore.release();
      }
    }

    return result.fold(
      (_) {
        if (_activeAcquireCount > 0) {
          _activeAcquireCount--;
        }
        return const Success(unit);
      },
      (error) {
        if (_messageIndicatesInvalidConnectionId(error)) {
          if (_activeAcquireCount > 0) {
            _activeAcquireCount--;
          }
          return const Success(unit);
        }
        _metrics?.recordPoolReleaseFailure();
        return Failure(
          OdbcFailureMapper.mapPoolError(
            error,
            operation: 'pool_release',
          ),
        );
      },
    );
  }

  @override
  Future<Result<void>> discard(String connectionId) async {
    var handshakeHeld = false;
    try {
      await _nativeHandshakeSemaphore.acquire(
        timeout: ConnectionConstants.defaultPoolAcquireTimeout,
      );
      handshakeHeld = true;
    } on TimeoutException {
      developer.log(
        'Native pool discard: handshake timeout; poolReleaseConnection anyway',
        name: 'connection_pool',
        level: 900,
      );
    }

    // odbc_fast 3.9.0: disconnect() returns ValidationError for pool-owned
    // connections. Pool connections must be returned via poolReleaseConnection,
    // which rolls back uncommitted work before making the slot available again.
    late Result<void> result;
    try {
      result = await _service.poolReleaseConnection(connectionId);
    } finally {
      if (handshakeHeld) {
        _nativeHandshakeSemaphore.release();
      }
    }

    return result.fold(
      (_) {
        if (_activeAcquireCount > 0) {
          _activeAcquireCount--;
        }
        return const Success(unit);
      },
      (error) {
        if (_messageIndicatesInvalidConnectionId(error)) {
          if (_activeAcquireCount > 0) {
            _activeAcquireCount--;
          }
          return const Success(unit);
        }
        _metrics?.recordPoolReleaseFailure();
        return Failure(
          OdbcFailureMapper.mapPoolError(
            error,
            operation: 'pool_discard',
          ),
        );
      },
    );
  }

  @override
  Future<Result<void>> closeAll() async {
    developer.log(
      'Closing all pools',
      name: 'connection_pool',
      level: 500,
    );

    final errors = <String>[];

    for (final poolId in _pools.values) {
      var handshakeHeld = false;
      try {
        await _nativeHandshakeSemaphore.acquire(
          timeout: ConnectionConstants.defaultPoolAcquireTimeout,
        );
        handshakeHeld = true;
      } on TimeoutException {
        developer.log(
          'Native pool closeAll: handshake timeout; poolClose anyway',
          name: 'connection_pool',
          level: 900,
        );
      }
      try {
        final result = await _service.poolClose(poolId);
        result.fold(
          (_) {},
          (error) => errors.add(_odbcErrorMessage(error)),
        );
      } finally {
        if (handshakeHeld) {
          _nativeHandshakeSemaphore.release();
        }
      }
    }

    _pools.clear();
    _poolCreationFutures.clear();
    _activeAcquireCount = 0;

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

  @override
  Future<Result<void>> recycle(String connectionString) async {
    final poolId = _pools.remove(connectionString);
    _poolCreationFutures.remove(connectionString);
    if (poolId == null) {
      return const Success(unit);
    }
    _metrics?.recordPoolRecycle();

    developer.log(
      'Recycling pool for connection',
      name: 'connection_pool',
      level: 800,
    );

    var handshakeHeld = false;
    try {
      await _nativeHandshakeSemaphore.acquire(
        timeout: ConnectionConstants.defaultPoolAcquireTimeout,
      );
      handshakeHeld = true;
    } on TimeoutException {
      developer.log(
        'Native pool recycle: handshake timeout; poolClose anyway',
        name: 'connection_pool',
        level: 900,
      );
    }

    late Result<void> closeResult;
    try {
      closeResult = await _service.poolClose(poolId);
    } finally {
      if (handshakeHeld) {
        _nativeHandshakeSemaphore.release();
      }
    }

    return closeResult.fold(
      (_) => const Success(unit),
      (error) => Failure(
        () {
          _metrics?.recordPoolRecycleFailure();
          return OdbcFailureMapper.mapPoolError(
            error,
            operation: 'pool_recycle',
          );
        }(),
      ),
    );
  }

  @override
  Future<Result<void>> warmUp(
    String connectionString, {
    int? warmUpCount,
  }) async {
    final count = warmUpCount ?? (_settings.poolSize / 2).ceil();
    final connectionIds = <String>[];
    final errors = <String>[];

    try {
      for (var i = 0; i < count; i++) {
        final result = await acquire(connectionString);
        result.fold(
          connectionIds.add,
          (error) => errors.add('warmup_acquire_${i + 1}: $error'),
        );
      }
    } finally {
      for (final id in connectionIds) {
        final cleanup = await release(id);
        cleanup.fold(
          (_) {},
          (error) => errors.add('warmup_release_$id: $error'),
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
  Future<Result<int>> getActiveCount({String? connectionString}) async {
    var totalActive = 0;

    final poolsToCount = connectionString == null
        ? _pools.values.toList(growable: false)
        : <int>[
            if (_pools[connectionString] case final int poolId) poolId,
          ];

    for (final poolId in poolsToCount) {
      final stateResult = await _service.poolGetState(poolId);
      if (stateResult.isError()) {
        return Failure(
          OdbcFailureMapper.mapPoolError(
            stateResult.exceptionOrNull()!,
            operation: 'pool_get_active_count',
          ),
        );
      }

      final state = stateResult.getOrThrow();
      totalActive += state.size - state.idle;
    }

    return Success(totalActive);
  }

  @override
  Future<Result<void>> healthCheckAll() async {
    final errors = <String>[];

    for (final poolId in _pools.values) {
      // odbc_fast 3.9.0: poolHealthCheck returns Failure(ConnectionError) for
      // unhealthy pools; Success(false) is no longer emitted.
      final result = await _service.poolHealthCheck(poolId);
      result.fold(
        (_) {},
        (error) => errors.add(_odbcErrorMessage(error)),
      );
    }

    if (errors.isNotEmpty) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          Exception(errors.join(', ')),
          operation: 'pool_health_check',
        ),
      );
    }

    return const Success(unit);
  }

  @override
  Map<String, Object?> getHealthDiagnostics() {
    return {
      'strategy': 'native',
      'native_pool_exposed': true,
      'lease_active_count': 0,
      'native_active_count': _activeAcquireCount,
    };
  }
}
