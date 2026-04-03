import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
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
class OdbcConnectionPool implements IConnectionPool {
  OdbcConnectionPool(
    this._service,
    this._settings, {
    Duration? acquireTimeout,
    MetricsCollector? metricsCollector,
  }) : _semaphore = PoolSemaphore(_settings.poolSize),
       _acquireTimeout = acquireTimeout ?? ConnectionConstants.defaultPoolAcquireTimeout,
       _metrics = metricsCollector;
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final PoolSemaphore _semaphore;
  final Duration _acquireTimeout;
  final MetricsCollector? _metrics;

  final Map<String, Set<String>> _leasedIdsByConnectionString = {};
  final Set<String> _leasedIds = {};

  @override
  Future<Result<String>> acquire(String connectionString) async {
    try {
      await _semaphore.acquire(
        timeout: _acquireTimeout,
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
        ),
      );
    }

    final options = OdbcConnectionOptionsBuilder.forQueryExecution(_settings);
    final connectResult = await _service.connect(
      connectionString,
      options: options,
    );

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
    final hadLease = _removeLeaseTracking(connectionId);
    if (hadLease) {
      _semaphore.release();
    }

    final disconnectResult = await _service.disconnect(connectionId);
    return disconnectResult.fold(
      (_) => const Success(unit),
      (_) => const Success(unit),
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
      final result = await _service.disconnect(id);
      result.fold(
        (_) {},
        (error) => errors.add(
          error is OdbcError ? error.message : error.toString(),
        ),
      );
      _semaphore.release();
    }
    _leasedIds.clear();
    _leasedIdsByConnectionString.clear();

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
    final ids = _leasedIdsByConnectionString.remove(connectionString);
    if (ids == null || ids.isEmpty) {
      return const Success(unit);
    }

    developer.log(
      'Recycling leased ODBC connections for connection string',
      name: 'connection_pool',
      level: 800,
    );

    for (final id in ids.toList(growable: false)) {
      await _service.disconnect(id);
      _leasedIds.remove(id);
      _semaphore.release();
    }
    return const Success(unit);
  }

  @override
  Future<Result<int>> getActiveCount() async {
    return Success(_leasedIds.length);
  }

  @override
  Future<Result<void>> healthCheckAll() async {
    return const Success(unit);
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
}
