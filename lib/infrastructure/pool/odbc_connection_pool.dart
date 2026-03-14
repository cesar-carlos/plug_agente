import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Pool de conexões ODBC usando pool nativo do odbc_fast.
///
/// Utiliza a API de pool nativo para gerenciamento automático de conexões,
/// health checks e isolamento correto entre consumers.
class OdbcConnectionPool implements IConnectionPool {
  OdbcConnectionPool(this._service, this._settings);
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;

  // connectionString -> poolId
  final Map<String, int> _pools = {};
  final Map<String, Future<Result<int>>> _poolCreationFutures = {};

  /// Helper para converter erros ODBC em String.
  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  /// Cria ou reutiliza pool para a connection string.
  Future<Result<int>> _getOrCreatePool(String connectionString) async {
    final existingPoolId = _pools[connectionString];
    if (existingPoolId != null) {
      return Success(existingPoolId);
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

  Future<Result<int>> _createPool(String connectionString) async {
    developer.log(
      'Creating native pool for connection',
      name: 'connection_pool',
      level: 500,
    );

    final poolResult = await _service.poolCreate(
      connectionString,
      _settings.poolSize,
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
        // Obter conexão do pool nativo
        final connResult = await _service.poolGetConnection(poolId);

        return connResult.fold(
          (connection) {
            developer.log(
              'Connection acquired from pool: ${connection.id}',
              name: 'connection_pool',
              level: 500,
            );
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
    developer.log(
      'Releasing connection back to pool: $connectionId',
      name: 'connection_pool',
      level: 500,
    );

    // Liberar conexão de volta ao pool nativo
    final result = await _service.poolReleaseConnection(connectionId);

    return result.fold(
      (_) => const Success(unit),
      (error) => Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'pool_release',
        ),
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

    developer.log(
      'Recycling pool for connection',
      name: 'connection_pool',
      level: 800,
    );

    final closeResult = await _service.poolClose(poolId);
    return closeResult.fold(
      (_) => const Success(unit),
      (error) => Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'pool_recycle',
        ),
      ),
    );
  }

  @override
  Future<Result<int>> getActiveCount() async {
    var totalActive = 0;

    for (final poolId in _pools.values) {
      final stateResult = await _service.poolGetState(poolId);
      stateResult.fold(
        (state) {
          // Active = size - idle
          totalActive += state.size - state.idle;
        },
        (_) {},
      );
    }

    return Success(totalActive);
  }

  /// Executa health check em todos os pools.
  Future<Result<void>> healthCheckAll() async {
    final errors = <String>[];

    for (final entry in _pools.entries) {
      final result = await _service.poolHealthCheck(entry.value);
      result.fold(
        (isHealthy) {
          if (!isHealthy) {
            errors.add('Pool ${entry.key} unhealthy');
          }
        },
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
}
