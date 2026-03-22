import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';

/// Limits concurrent in-flight ODBC leases.
///
/// Invariant: `_active` counts slots currently granted. When [leave] completes
/// a waiter instead of decrementing, that waiter takes over the freed slot
/// without a second `enter` increment — the slot is transferred from the
/// releaser to the next acquirer.
final class _LeaseLimiter {
  _LeaseLimiter({required int maxLeases}) : _maxLeases = maxLeases > 0 ? maxLeases : 1;

  final int _maxLeases;
  int _active = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> enter() async {
    if (_active < _maxLeases) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void leave() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  void failWaiters(Object error, StackTrace stackTrace) {
    for (final c in _waiters) {
      if (!c.isCompleted) {
        c.completeError(error, stackTrace);
      }
    }
    _waiters.clear();
  }
}

/// Aluga uma conexão ODBC por consulta via [OdbcService.connect] com
/// [ConnectionOptions] completos (buffer alinhado às configurações do app).
///
/// Evita falha `Buffer too small` em `poolReleaseConnection` do pool nativo
/// do `odbc_fast`, que não associa `maxResultBufferBytes` a conexões alugadas
/// do pool (caindo em buffer pequeno no worker).
class OdbcConnectionPool implements IConnectionPool {
  OdbcConnectionPool(this._service, this._settings);
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;

  final Map<String, Set<String>> _leasedIdsByConnectionString = {};
  final Set<String> _leasedIds = {};

  _LeaseLimiter? _leaseLimiterInstance;

  _LeaseLimiter _leases() => _leaseLimiterInstance ??= _LeaseLimiter(
    maxLeases: _settings.poolSize > 0 ? _settings.poolSize : ConnectionConstants.defaultPoolSize,
  );

  void _releaseLeaseSlot() {
    _leaseLimiterInstance?.leave();
  }

  @override
  Future<Result<String>> acquire(String connectionString) async {
    try {
      await _leases().enter();
    } on Object catch (error) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
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
        _releaseLeaseSlot();
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
    final disconnectResult = await _service.disconnect(connectionId);
    return disconnectResult.fold(
      (_) {
        _leasedIds.remove(connectionId);
        for (final entry in _leasedIdsByConnectionString.entries) {
          entry.value.remove(connectionId);
        }
        _leasedIdsByConnectionString.removeWhere((_, ids) => ids.isEmpty);
        _releaseLeaseSlot();
        return const Success(unit);
      },
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'pool_release',
        ),
      ),
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
    }
    _leasedIds.clear();
    _leasedIdsByConnectionString.clear();
    _leaseLimiterInstance?.failWaiters(
      StateError('ODBC lease pool closed'),
      StackTrace.current,
    );
    _leaseLimiterInstance = null;

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

    final idList = ids.toList(growable: false);
    final errors = <String>[];
    for (final id in idList) {
      final disconnectResult = await _service.disconnect(id);
      disconnectResult.fold(
        (_) {},
        (error) => errors.add(
          error is OdbcError ? error.message : error.toString(),
        ),
      );
      _leasedIds.remove(id);
      _releaseLeaseSlot();
    }

    if (errors.isNotEmpty) {
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
  Future<Result<int>> getActiveCount() async {
    return Success(_leasedIds.length);
  }

  @override
  Future<Result<void>> healthCheckAll() async {
    return const Success(unit);
  }
}
