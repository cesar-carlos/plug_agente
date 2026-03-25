import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';

/// Limits concurrent in-flight ODBC leases.
///
/// Invariant: `_active` counts slots currently granted. When [leave] completes
/// a waiter instead of decrementing, that waiter takes over the freed slot
/// without a second `enter` increment — the slot is transferred from the
/// releaser to the next acquirer.
final class _LeaseLimiter {
  _LeaseLimiter({
    required int maxLeases,
    void Function(int activeCount, int waiterCount)? onStateChanged,
  }) : _maxLeases = maxLeases > 0 ? maxLeases : 1,
       _onStateChanged = onStateChanged;

  final int _maxLeases;
  final void Function(int activeCount, int waiterCount)? _onStateChanged;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  void _notifyStateChanged() {
    _onStateChanged?.call(_active, _waiters.length);
  }

  Future<void> enter() async {
    if (_active < _maxLeases) {
      _active++;
      _notifyStateChanged();
      return;
    }
    final completer = Completer<void>();
    _waiters.addLast(completer);
    _notifyStateChanged();
    await completer.future;
  }

  void leave() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _active--;
    }
    _notifyStateChanged();
  }

  void failWaiters(Object error, StackTrace stackTrace) {
    for (final c in _waiters) {
      if (!c.isCompleted) {
        c.completeError(error, stackTrace);
      }
    }
    _waiters.clear();
    _notifyStateChanged();
  }
}

final class _IdleConnectionEntry {
  const _IdleConnectionEntry({
    required this.connectionId,
    required this.releasedAt,
  });

  final String connectionId;
  final DateTime releasedAt;
}

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
    MetricsCollector? metricsCollector,
    Duration? idleConnectionTtl,
  }) : _metrics = metricsCollector,
       _idleTtlOverride = idleConnectionTtl;
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final MetricsCollector? _metrics;
  final Duration? _idleTtlOverride;

  Duration get _idleConnectionTtl {
    final override = _idleTtlOverride;
    if (override != null) {
      return override;
    }
    final seconds = _settings.leaseIdleTtlSeconds;
    if (seconds <= 0) {
      return Duration.zero;
    }
    return Duration(
      seconds: seconds.clamp(1, ConnectionConstants.maxLeaseIdleTtlSeconds),
    );
  }

  final Map<String, Set<String>> _leasedIdsByConnectionString = {};
  final Set<String> _leasedIds = {};
  final Map<String, String> _leasedConnectionStringById = {};
  final Map<String, List<_IdleConnectionEntry>> _idleByConnectionString = {};
  final Set<String> _idleIds = {};

  /// Serializes [warmIdleLeases] per connection string to avoid duplicate opens.
  final Map<String, Future<void>> _warmupSerialByConnectionString = {};

  _LeaseLimiter? _leaseLimiterInstance;

  _LeaseLimiter _leases() => _leaseLimiterInstance ??= _LeaseLimiter(
    maxLeases: _settings.poolSize > 0 ? _settings.poolSize : ConnectionConstants.defaultPoolSize,
    onStateChanged: (int activeCount, int waiterCount) {
      _metrics?.recordConnectionPoolActivePeak(activeCount);
      _metrics?.recordConnectionPoolWaitersPeak(waiterCount);
    },
  );

  void _releaseLeaseSlot() {
    _leaseLimiterInstance?.leave();
  }

  int get _maxLeases => _settings.poolSize > 0 ? _settings.poolSize : ConnectionConstants.defaultPoolSize;

  void _trackLeasedConnection(String connectionId, String connectionString) {
    _leasedIdsByConnectionString.putIfAbsent(connectionString, () => <String>{}).add(connectionId);
    _leasedIds.add(connectionId);
    _leasedConnectionStringById[connectionId] = connectionString;
  }

  void _untrackLeasedConnection(String connectionId) {
    final connectionString = _leasedConnectionStringById.remove(connectionId);
    _leasedIds.remove(connectionId);
    if (connectionString != null) {
      final ids = _leasedIdsByConnectionString[connectionString];
      if (ids != null) {
        ids.remove(connectionId);
        if (ids.isEmpty) {
          _leasedIdsByConnectionString.remove(connectionString);
        }
      }
      return;
    }
    for (final entry in _leasedIdsByConnectionString.entries) {
      entry.value.remove(connectionId);
    }
    _leasedIdsByConnectionString.removeWhere((_, ids) => ids.isEmpty);
  }

  Future<void> _disconnectBestEffort(String connectionId) async {
    final result = await _service.disconnect(connectionId);
    result.fold(
      (_) {
        _idleIds.remove(connectionId);
      },
      (error) {
        developer.log(
          'Failed to disconnect expired idle lease connection',
          name: 'connection_pool',
          level: 900,
          error: error,
        );
      },
    );
  }

  Future<void> _purgeExpiredIdleConnections(String connectionString) async {
    if (_idleConnectionTtl <= Duration.zero) {
      return;
    }
    final now = DateTime.now();
    final entries = _idleByConnectionString[connectionString];
    if (entries == null || entries.isEmpty) {
      return;
    }

    final expiredIds = <String>[];
    entries.removeWhere((entry) {
      final expired = now.difference(entry.releasedAt) > _idleConnectionTtl;
      if (expired) {
        expiredIds.add(entry.connectionId);
      }
      return expired;
    });
    if (entries.isEmpty) {
      _idleByConnectionString.remove(connectionString);
    }

    if (expiredIds.isNotEmpty) {
      await Future.wait(
        expiredIds.map(_disconnectBestEffort),
      );
    }
  }

  String? _takeIdleConnection(String connectionString) {
    final entries = _idleByConnectionString[connectionString];
    if (entries == null || entries.isEmpty) {
      return null;
    }
    final entry = entries.removeLast();
    if (entries.isEmpty) {
      _idleByConnectionString.remove(connectionString);
    }
    _idleIds.remove(entry.connectionId);
    return entry.connectionId;
  }

  bool _tryReturnConnectionToIdle(
    String connectionId,
    String connectionString,
  ) {
    if (_idleConnectionTtl <= Duration.zero) {
      return false;
    }
    final entries = _idleByConnectionString.putIfAbsent(
      connectionString,
      () => <_IdleConnectionEntry>[],
    );
    if (entries.length >= _maxLeases) {
      return false;
    }
    entries.add(
      _IdleConnectionEntry(
        connectionId: connectionId,
        releasedAt: DateTime.now(),
      ),
    );
    _idleIds.add(connectionId);
    return true;
  }

  @override
  Future<Result<String>> acquire(String connectionString) async {
    final waitStopwatch = Stopwatch()..start();
    final acquireStopwatch = Stopwatch()..start();
    try {
      await _leases().enter();
    } on Object catch (error) {
      waitStopwatch.stop();
      acquireStopwatch.stop();
      _metrics?.recordConnectionPoolWaitLatency(waitStopwatch.elapsed);
      _metrics?.recordConnectionPoolAcquireLatency(acquireStopwatch.elapsed);
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'pool_acquire',
        ),
      );
    }
    waitStopwatch.stop();
    _metrics?.recordConnectionPoolWaitLatency(waitStopwatch.elapsed);

    await _purgeExpiredIdleConnections(connectionString);
    final reusedConnectionId = _takeIdleConnection(connectionString);
    if (reusedConnectionId != null) {
      acquireStopwatch.stop();
      _metrics?.recordConnectionPoolAcquireLatency(acquireStopwatch.elapsed);
      _trackLeasedConnection(reusedConnectionId, connectionString);
      developer.log(
        'Reusing idle ODBC lease connection $reusedConnectionId',
        name: 'connection_pool',
        level: 500,
      );
      return Success(reusedConnectionId);
    }

    final options = OdbcConnectionOptionsBuilder.forQueryExecution(_settings);
    final connectResult = await _service.connect(
      connectionString,
      options: options,
    );
    acquireStopwatch.stop();
    _metrics?.recordConnectionPoolAcquireLatency(acquireStopwatch.elapsed);

    return connectResult.fold(
      (Connection connection) {
        _trackLeasedConnection(connection.id, connectionString);
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
    final connectionString = _leasedConnectionStringById[connectionId];
    _untrackLeasedConnection(connectionId);
    if (connectionString != null && _tryReturnConnectionToIdle(connectionId, connectionString)) {
      _metrics?.recordConnectionPoolReleaseLatency(Duration.zero);
      _releaseLeaseSlot();
      return const Success(unit);
    }

    final stopwatch = Stopwatch()..start();
    final disconnectResult = await _service.disconnect(connectionId);
    stopwatch.stop();
    _metrics?.recordConnectionPoolReleaseLatency(stopwatch.elapsed);
    return disconnectResult.fold(
      (_) {
        _idleIds.remove(connectionId);
        _releaseLeaseSlot();
        return const Success(unit);
      },
      (error) {
        developer.log(
          'Disconnect failed during lease pool release; reclaiming lease slot '
          'to avoid indefinite pool exhaustion. If this repeats, call '
          'recycle() for the connection string.',
          name: 'connection_pool',
          level: 900,
          error: error,
        );
        _metrics?.recordConnectionPoolLeaseSlotReclaimedAfterDisconnectFailure();
        _releaseLeaseSlot();
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'pool_release',
          ),
        );
      },
    );
  }

  @override
  Future<Result<void>> warmIdleLeases(String connectionString) async {
    if (_settings.leaseWarmupCount <= 0 || _idleConnectionTtl <= Duration.zero) {
      return const Success(unit);
    }

    final previous = _warmupSerialByConnectionString[connectionString];
    final gate = Completer<void>();
    _warmupSerialByConnectionString[connectionString] = gate.future;
    try {
      if (previous != null) {
        await previous;
      }
      return await _warmIdleLeasesUnderLock(connectionString);
    } finally {
      gate.complete();
      if (identical(_warmupSerialByConnectionString[connectionString], gate.future)) {
        _warmupSerialByConnectionString.remove(connectionString);
      }
    }
  }

  Future<Result<void>> _warmOneIdleLease(String connectionString) async {
    try {
      await _leases().enter();
    } on Object catch (error) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'pool_warmup_lease',
        ),
      );
    }

    final options = OdbcConnectionOptionsBuilder.forQueryExecution(_settings);
    final connectResult = await _service.connect(
      connectionString,
      options: options,
    );

    if (connectResult.isError()) {
      _releaseLeaseSlot();
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          connectResult.exceptionOrNull()!,
          operation: 'pool_warmup_connect',
        ),
      );
    }

    final connectionId = connectResult.getOrNull()!.id;
    _trackLeasedConnection(connectionId, connectionString);
    final released = await release(connectionId);
    if (released.isError()) {
      return released;
    }
    return const Success(unit);
  }

  Future<Result<void>> _warmIdleLeasesUnderLock(String connectionString) async {
    final target = _settings.leaseWarmupCount.clamp(
      0,
      ConnectionConstants.maxLeaseWarmupCount,
    );
    final cappedTarget = target > _maxLeases ? _maxLeases : target;
    final existingIdle = _idleByConnectionString[connectionString]?.length ?? 0;
    final need = cappedTarget - existingIdle;
    if (need <= 0) {
      return const Success(unit);
    }

    final results = await Future.wait(
      List<Future<Result<void>>>.generate(
        need,
        (_) => _warmOneIdleLease(connectionString),
      ),
    );
    for (final r in results) {
      if (r.isError()) {
        return Failure(r.exceptionOrNull()!);
      }
    }
    return const Success(unit);
  }

  @override
  Future<Result<void>> closeAll() async {
    developer.log(
      'Disconnecting all leased and idle ODBC connections',
      name: 'connection_pool',
      level: 500,
    );

    final errors = <String>[];
    final ids = <String>{
      ..._leasedIds,
      ..._idleIds,
    }.toList(growable: false);
    await Future.wait(
      ids.map((String id) async {
        final result = await _service.disconnect(id);
        result.fold(
          (_) {},
          (Object error) => errors.add(
            error is OdbcError ? error.message : error.toString(),
          ),
        );
      }),
    );
    _leasedIds.clear();
    _leasedConnectionStringById.clear();
    _leasedIdsByConnectionString.clear();
    _idleIds.clear();
    _idleByConnectionString.clear();
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
    final leasedIds = _leasedIdsByConnectionString.remove(connectionString);
    final idleEntries = _idleByConnectionString.remove(connectionString);
    final ids = <String>{
      ...?leasedIds,
      ...?idleEntries?.map((entry) => entry.connectionId),
    };
    if (ids.isEmpty) {
      return const Success(unit);
    }

    developer.log(
      'Recycling leased ODBC connections for connection string',
      name: 'connection_pool',
      level: 800,
    );

    final errors = <String>[];
    for (final id in ids) {
      final disconnectResult = await _service.disconnect(id);
      disconnectResult.fold(
        (_) {},
        (error) => errors.add(
          error is OdbcError ? error.message : error.toString(),
        ),
      );
      _idleIds.remove(id);
      if (_leasedIds.remove(id)) {
        _leasedConnectionStringById.remove(id);
        _releaseLeaseSlot();
      }
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
    final overlap = _leasedIds.intersection(_idleIds);
    if (overlap.isNotEmpty) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError('Lease pool invariant violated: id in leased and idle: $overlap'),
          operation: 'pool_health_check',
        ),
      );
    }
    if (_leasedIds.length > _maxLeases) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError(
            'Lease pool invariant violated: leased ${_leasedIds.length} '
            'exceeds max $_maxLeases',
          ),
          operation: 'pool_health_check',
        ),
      );
    }
    return const Success(unit);
  }
}
