import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Pool ODBC usando pool nativo do `odbc_fast` (conexões do pool não recebem
/// `ConnectionOptions` no repositório e podem cair em buffer ~512 KiB no
/// worker). Mantido para testes; o app usa lease em `odbc_connection_pool.dart`.
class OdbcNativeConnectionPool implements IConnectionPool {
  OdbcNativeConnectionPool(
    this._service,
    this._settings, {
    MetricsCollector? metricsCollector,
  }) : _metrics = metricsCollector;
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final MetricsCollector? _metrics;

  final Map<String, int> _pools = {};
  final Map<String, Future<Result<int>>> _poolCreationFutures = {};

  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  String _poolConnectionString(String connectionString) {
    if (_settings.nativePoolTestOnCheckout) {
      return connectionString;
    }

    if (connectionString.toLowerCase().contains('pooltestoncheckout=')) {
      return connectionString;
    }

    return '$connectionString;PoolTestOnCheckout=false';
  }

  PoolOptions get _poolOptions {
    return const PoolOptions(
      idleTimeout: ConnectionConstants.defaultNativePoolIdleTimeout,
      maxLifetime: ConnectionConstants.defaultNativePoolMaxLifetime,
      connectionTimeout: ConnectionConstants.defaultNativePoolConnectionTimeout,
    );
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
    return result;
  }

  Future<Result<Map<String, Object?>>> getDetailedState(
    String connectionString,
  ) async {
    final poolId = _pools[connectionString];
    if (poolId == null) {
      return const Success(<String, Object?>{
        'available': false,
        'reason': 'pool_not_created',
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

    final poolResult = await _service.poolCreate(
      _poolConnectionString(connectionString),
      _settings.poolSize,
      options: _poolOptions,
    );

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
  Future<Result<String>> acquire(String connectionString) async {
    final poolResult = await _getOrCreatePool(connectionString);

    return poolResult.fold(
      (poolId) async {
        final connResult = await _service.poolGetConnection(poolId);

        return connResult.fold(
          (connection) {
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
    final result = await _service.poolReleaseConnection(connectionId);

    return result.fold(
      (_) => const Success(unit),
      (error) => Failure(
        () {
          _metrics?.recordPoolReleaseFailure();
          return OdbcFailureMapper.mapPoolError(
            error,
            operation: 'pool_release',
          );
        }(),
      ),
    );
  }

  @override
  Future<Result<void>> discard(String connectionId) async {
    final result = await _service.disconnect(connectionId);

    return result.fold(
      (_) => const Success(unit),
      (error) => Failure(
        () {
          _metrics?.recordPoolReleaseFailure();
          return OdbcFailureMapper.mapPoolError(
            error,
            operation: 'pool_discard',
          );
        }(),
      ),
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
      final result = await _service.poolClose(poolId);
      result.fold(
        (_) {},
        (error) => errors.add(_odbcErrorMessage(error)),
      );
    }

    _pools.clear();
    _poolCreationFutures.clear();

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

    final closeResult = await _service.poolClose(poolId);
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
  Future<Result<int>> getActiveCount() async {
    var totalActive = 0;

    for (final poolId in _pools.values) {
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

    var poolIndex = 0;
    for (final entry in _pools.entries) {
      final result = await _service.poolHealthCheck(entry.value);
      result.fold(
        (isHealthy) {
          if (!isHealthy) {
            errors.add('Pool #$poolIndex unhealthy');
          }
        },
        (error) => errors.add(_odbcErrorMessage(error)),
      );
      poolIndex++;
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
}
