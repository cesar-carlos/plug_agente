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
import 'package:plug_agente/infrastructure/logging/odbc_resilience_log.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';

/// ODBC pool backed by `odbc_fast` native pooling with app-level
/// [PoolOptions] and default [ConnectionOptions] on `poolCreate`.
///
/// Per-checkout [ConnectionOptions] are stored by `odbc_fast` on the Dart
/// connection state via `poolGetConnection(options:)` (query timeouts, buffers,
/// lazyStrings). The native FFI checkout itself still returns an existing
/// pooled handle; options do not re-run ODBC login.
class OdbcNativeConnectionPool
    implements
        IConnectionPool,
        ITimedConnectionPoolAcquire,
        IConnectionPoolDiagnostics,
        IConnectionPoolWarmUp,
        IConnectionPoolLiveProbe,
        IOdbcNativeBulkInsertPool {
  OdbcNativeConnectionPool(
    this._service,
    this._settings, {
    MetricsCollector? metricsCollector,
    OdbcProfileRecommendedOptions? recommendedOptions,
  }) : _metrics = metricsCollector,
       _recommendedOptions = recommendedOptions,
       _nativeCheckoutSemaphore = PoolSemaphore(
         ConnectionConstants.nativePoolCheckoutConcurrency(_settings.poolSize),
       ),
       _nativeReturnSemaphore = PoolSemaphore(
         ConnectionConstants.nativePoolReturnConcurrency(_settings.poolSize),
       );
  final OdbcService _service;
  final IOdbcConnectionSettings _settings;
  final OdbcProfileRecommendedOptions? _recommendedOptions;
  final MetricsCollector? _metrics;
  final PoolSemaphore _nativeCheckoutSemaphore;
  final PoolSemaphore _nativeReturnSemaphore;

  final Map<String, int> _pools = {};
  final Map<String, Future<Result<int>>> _poolCreationFutures = {};
  final Map<String, int> _poolGenerations = <String, int>{};
  final Map<String, String> _connectionOwners = <String, String>{};
  final Map<String, int> _activeByConnectionString = <String, int>{};
  final Set<String> _quarantinedConnectionStrings = <String>{};
  final Map<String, Timer> _quarantineRetryTimers = <String, Timer>{};
  final Map<String, int> _quarantineRetryAttempts = <String, int>{};
  final Set<String> _slowQuarantineRecoveryLogged = <String>{};
  int _activeAcquireCount = 0;
  final Map<int, _CachedPoolState> _poolStateCache = <int, _CachedPoolState>{};

  static const int _maxQuarantineRetries = 5;
  static const Duration _poolStateCacheTtl = Duration(milliseconds: 500);
  static const Duration _quarantineRetryBaseDelay = Duration(milliseconds: 250);
  static const Duration _quarantineRetryMaxDelay = Duration(seconds: 30);

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
    final plugDefaults = PoolOptions(
      idleTimeout: ConnectionConstants.defaultNativePoolIdleTimeout,
      maxLifetime: ConnectionConstants.defaultNativePoolMaxLifetime,
      connectionTimeout: ConnectionConstants.defaultNativePoolConnectionTimeout,
      sessionResetOnCheckout: _settings.nativePoolSessionResetOnCheckout,
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

  ConnectionOptions _defaultConnectionOptions(String connectionString) {
    return OdbcConnectionOptionsBuilder.forQueryExecution(_settings).toOdbcConnectionOptions(
      recommendedProfile: _recommendedOptions?.connection,
      lazyStrings: OdbcRecommendedOptionsMerger.lazyStringsForConnectionString(
        connectionString,
      ),
    );
  }

  ConnectionOptions? _checkoutConnectionOptions(
    String connectionString,
    ConnectionAcquireOptions? options,
  ) {
    if (options == null) {
      return null;
    }
    return options.toOdbcConnectionOptions(
      recommendedProfile: _recommendedOptions?.connection,
      lazyStrings: OdbcRecommendedOptionsMerger.lazyStringsForConnectionString(
        connectionString,
      ),
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

    final generation = _poolGenerations.putIfAbsent(connectionString, () => 0);
    final creationFuture = _createPool(connectionString, generation: generation);
    _poolCreationFutures[connectionString] = creationFuture;
    final result = await creationFuture;
    if (identical(_poolCreationFutures[connectionString], creationFuture)) {
      _poolCreationFutures.remove(connectionString);
    }

    return result;
  }

  Future<Result<Map<String, Object?>>> getDetailedState(
    String connectionString,
  ) async {
    if (_quarantinedConnectionStrings.contains(connectionString)) {
      return const Success(<String, Object?>{
        'available': false,
        'state': 'quarantined',
        'reason': 'native_pool_quarantined',
      });
    }
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

  Future<Result<int>> _createPool(
    String connectionString, {
    required int generation,
  }) async {
    developer.log(
      'Creating native pool for connection',
      name: 'connection_pool',
      level: 500,
    );

    try {
      await _nativeCheckoutSemaphore.acquire(
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
        connectionOptions: _defaultConnectionOptions(connectionString),
      );
    } finally {
      _nativeCheckoutSemaphore.release();
    }

    if (poolResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          poolResult.exceptionOrNull()!,
          operation: 'pool_create',
        ),
      );
    }

    final poolId = poolResult.getOrThrow();
    if (_poolGenerations[connectionString] != generation) {
      // A recycle/close occurred while the native worker was creating this
      // pool. Never publish a stale handle into the new generation.
      await _service.poolClose(poolId);
      return Failure(
        OdbcFailureMapper.mapPoolError(
          StateError('Pool was invalidated during creation; retry acquisition.'),
          operation: 'pool_acquire',
          context: const <String, dynamic>{
            'reason': OdbcContextConstants.poolNotCreatedReason,
            'retryable': true,
          },
        ),
      );
    }

    _pools[connectionString] = poolId;
    developer.log(
      'Native pool created',
      name: 'connection_pool',
      level: 500,
    );
    return Success(poolId);
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
    final effectiveAcquireTimeout = acquireTimeout ?? ConnectionConstants.defaultPoolAcquireTimeout;
    final stopwatch = Stopwatch()..start();
    if (_quarantinedConnectionStrings.contains(connectionString)) {
      _scheduleQuarantineRecovery(connectionString);
      return Failure(
        domain.ConnectionFailure.withContext(
          message: 'Native ODBC pool is being recycled after an unsafe execution',
          context: const <String, Object?>{
            'reason': 'native_pool_quarantined',
            'retryable': true,
          },
        ),
      );
    }
    final poolResult = await _getOrCreatePool(connectionString);

    return poolResult.fold(
      (poolId) async {
        try {
          final remainingAcquireBudget = effectiveAcquireTimeout - stopwatch.elapsed;
          if (remainingAcquireBudget <= Duration.zero) {
            throw TimeoutException('Native pool acquisition budget exhausted');
          }
          await _nativeCheckoutSemaphore.acquire(
            timeout: remainingAcquireBudget,
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
          final checkoutOptions = _checkoutConnectionOptions(
            connectionString,
            options,
          );
          connResult = checkoutOptions == null
              ? await _service.poolGetConnection(poolId)
              : await _service.poolGetConnection(
                  poolId,
                  options: checkoutOptions,
                );
        } finally {
          _nativeCheckoutSemaphore.release();
        }

        return connResult.fold(
          (connection) {
            _activeAcquireCount++;
            _poolStateCache.clear();
            _connectionOwners[connection.id] = connectionString;
            _activeByConnectionString[connectionString] = (_activeByConnectionString[connectionString] ?? 0) + 1;
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
    final connectionString = _connectionOwners.remove(connectionId);
    var handshakeHeld = false;
    try {
      await _nativeReturnSemaphore.acquire(
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
        _nativeReturnSemaphore.release();
      }
    }

    return result.fold(
      (_) {
        _decrementActive(connectionString);
        _scheduleQuarantineRecoveryIfDrained(connectionString);
        return const Success(unit);
      },
      (error) {
        if (_messageIndicatesInvalidConnectionId(error)) {
          _decrementActive(connectionString);
          _scheduleQuarantineRecoveryIfDrained(connectionString);
          return const Success(unit);
        }
        // The caller can no longer safely own a handle whose release failed.
        // Account for it as drained and quarantine its native pool so a later
        // checkout cannot reuse a potentially poisoned connection.
        if (connectionString != null) {
          _quarantinedConnectionStrings.add(connectionString);
          _decrementActive(connectionString);
          _scheduleQuarantineRecoveryIfDrained(connectionString);
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
  Future<Result<void>> discard(
    String connectionId, {
    PoolDiscardReason reason = PoolDiscardReason.suspectConnection,
  }) async {
    final connectionString = _connectionOwners.remove(connectionId);
    if (connectionString == null) {
      // An unknown pooled connection cannot safely be associated with one pool.
      _quarantinedConnectionStrings.addAll(_pools.keys);
      _pools.keys.forEach(_scheduleQuarantineRecovery);
    } else if (reason == PoolDiscardReason.poisonedPool) {
      _quarantinedConnectionStrings.add(connectionString);
    }
    var handshakeHeld = false;
    try {
      await _nativeReturnSemaphore.acquire(
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
        _nativeReturnSemaphore.release();
      }
    }

    return result.fold(
      (_) {
        _decrementActive(connectionString);
        _scheduleQuarantineRecoveryIfDrained(connectionString);
        return const Success(unit);
      },
      (error) {
        if (_messageIndicatesInvalidConnectionId(error)) {
          _decrementActive(connectionString);
          _scheduleQuarantineRecoveryIfDrained(connectionString);
          return const Success(unit);
        }
        // Checkin failed, so the handle may still be poisoned. Quarantine the
        // DSN even when the caller only asked to discard one connection.
        if (connectionString != null) {
          _quarantinedConnectionStrings.add(connectionString);
        }
        _decrementActive(connectionString);
        _scheduleQuarantineRecoveryIfDrained(connectionString);
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

    final invalidatedConnectionStrings = <String>{
      ..._pools.keys,
      ..._poolCreationFutures.keys,
    };
    invalidatedConnectionStrings.forEach(_invalidatePoolGeneration);

    for (final poolId in _pools.values) {
      var handshakeHeld = false;
      try {
        await _nativeReturnSemaphore.acquire(
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
          _nativeReturnSemaphore.release();
        }
      }
    }

    _pools.clear();
    _poolStateCache.clear();
    _poolCreationFutures.clear();
    _connectionOwners.clear();
    _activeByConnectionString.clear();
    _quarantinedConnectionStrings.clear();
    _quarantineRetryAttempts.clear();
    _slowQuarantineRecoveryLogged.clear();
    for (final timer in _quarantineRetryTimers.values) {
      timer.cancel();
    }
    _quarantineRetryTimers.clear();
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
    _invalidatePoolGeneration(connectionString);
    final poolId = _pools.remove(connectionString);
    _poolStateCache.remove(poolId);
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
      await _nativeReturnSemaphore.acquire(
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
        _nativeReturnSemaphore.release();
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

    developer.log(
      'Warming up native pool with $count connections',
      name: 'connection_pool',
      level: 800,
    );

    try {
      final handshakeBatchSize = _nativeCheckoutSemaphore.maxConcurrent;
      for (var offset = 0; offset < count; offset += handshakeBatchSize) {
        final batchEnd = offset + handshakeBatchSize < count ? offset + handshakeBatchSize : count;
        final batchResults = await Future.wait(
          List.generate(
            batchEnd - offset,
            (_) => acquire(connectionString),
          ),
        );
        for (var batchIndex = 0; batchIndex < batchResults.length; batchIndex++) {
          final globalIndex = offset + batchIndex + 1;
          batchResults[batchIndex].fold(
            connectionIds.add,
            (error) {
              developer.log(
                'Native warm-up connection $globalIndex/$count failed',
                name: 'connection_pool',
                level: 900,
                error: error,
              );
              errors.add('warmup_acquire_$globalIndex: $error');
            },
          );
        }
      }

      developer.log(
        'Native pool warm-up completed: ${connectionIds.length}/$count connections',
        name: 'connection_pool',
        level: 800,
      );
    } finally {
      final cleanups = await Future.wait(connectionIds.map(release));
      for (var index = 0; index < cleanups.length; index++) {
        cleanups[index].fold(
          (_) {},
          (error) {
            final id = connectionIds[index];
            developer.log(
              'Native warm-up cleanup failed for $id',
              name: 'connection_pool',
              level: 900,
              error: error,
            );
            errors.add('warmup_release_$id: $error');
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
  Future<Result<int>> getActiveCount({String? connectionString}) async {
    var totalActive = 0;

    final poolsToCount = connectionString == null
        ? _pools.values.toList(growable: false)
        : <int>[
            if (_pools[connectionString] case final int poolId) poolId,
          ];

    for (final poolId in poolsToCount) {
      final stateResult = await _cachedPoolState(poolId);
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

  Future<void> _reconcileActiveCount() async {
    final activeResult = await getActiveCount();
    if (activeResult.isSuccess()) {
      _activeAcquireCount = activeResult.getOrThrow();
    }
  }

  @override
  Future<Result<void>> healthCheckAll() async {
    await _reconcileActiveCount();

    final errors = <String>[];

    for (final poolId in _pools.values) {
      // poolHealthCheck checkouts a real connection. Frequent health uses the
      // detailed state snapshot instead.
      final result = await _service.poolGetStateDetailed(poolId);
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
  Future<Result<void>> probeLiveConnections() async {
    final errors = <String>[];
    for (final poolId in _pools.values) {
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
      'effective_strategy': 'native',
      'native_pool_exposed': true,
      'native_circuit_open': false,
      'native_skip_reason': null,
      'lease_active_count': 0,
      'native_active_count': _activeAcquireCount,
      'native_quarantined_pool_count': _quarantinedConnectionStrings.length,
      'native_quarantine_recovery_scheduled': _quarantineRetryTimers.length,
      'native_quarantine_slow_recovery': _slowQuarantineRecoveryLogged.length,
    };
  }

  Future<Result<PoolState>> _cachedPoolState(int poolId) async {
    final cached = _poolStateCache[poolId];
    if (cached != null && DateTime.now().difference(cached.capturedAt) < _poolStateCacheTtl) {
      return Success(cached.state);
    }
    final stateResult = await _service.poolGetState(poolId);
    if (stateResult.isSuccess()) {
      _poolStateCache[poolId] = _CachedPoolState(
        stateResult.getOrThrow(),
        DateTime.now(),
      );
    }
    return stateResult;
  }

  void _decrementActive(String? connectionString) {
    _poolStateCache.clear();
    if (_activeAcquireCount > 0) {
      _activeAcquireCount--;
    }
    if (connectionString == null) {
      return;
    }
    final active = _activeByConnectionString[connectionString] ?? 0;
    if (active <= 1) {
      _activeByConnectionString.remove(connectionString);
    } else {
      _activeByConnectionString[connectionString] = active - 1;
    }
  }

  void _scheduleQuarantineRecoveryIfDrained(String? connectionString) {
    if (connectionString != null && _quarantinedConnectionStrings.contains(connectionString)) {
      _scheduleQuarantineRecovery(connectionString);
    }
  }

  void _scheduleQuarantineRecovery(String connectionString) {
    if (!_quarantinedConnectionStrings.contains(connectionString) ||
        _quarantineRetryTimers.containsKey(connectionString)) {
      return;
    }
    final attempt = _quarantineRetryAttempts[connectionString] ?? 0;
    final Duration delay;
    if (attempt >= _maxQuarantineRetries) {
      delay = _quarantineRetryMaxDelay;
      if (_slowQuarantineRecoveryLogged.add(connectionString)) {
        OdbcResilienceLog.warning(
          event: 'native_quarantine_slow_recovery',
          connectionString: connectionString,
          attempt: attempt,
          delayMs: delay.inMilliseconds,
        );
      }
    } else {
      final multiplier = 1 << attempt;
      final rawDelay = _quarantineRetryBaseDelay * multiplier;
      delay = rawDelay > _quarantineRetryMaxDelay ? _quarantineRetryMaxDelay : rawDelay;
    }
    _quarantineRetryTimers[connectionString] = Timer(delay, () {
      _quarantineRetryTimers.remove(connectionString);
      unawaited(_recoverQuarantinedPool(connectionString));
    });
  }

  Future<void> _recoverQuarantinedPool(String connectionString) async {
    if (!_quarantinedConnectionStrings.contains(connectionString)) {
      return;
    }
    if ((_activeByConnectionString[connectionString] ?? 0) > 0) {
      _scheduleQuarantineRecovery(connectionString);
      return;
    }
    final recycleResult = await recycle(connectionString);
    if (recycleResult.isSuccess()) {
      _quarantinedConnectionStrings.remove(connectionString);
      _quarantineRetryAttempts.remove(connectionString);
      _slowQuarantineRecoveryLogged.remove(connectionString);
      OdbcResilienceLog.operational(
        event: 'quarantine_recovered',
        connectionString: connectionString,
      );
      return;
    }
    _quarantineRetryAttempts[connectionString] = (_quarantineRetryAttempts[connectionString] ?? 0) + 1;
    _scheduleQuarantineRecovery(connectionString);
  }

  void _invalidatePoolGeneration(String connectionString) {
    _poolGenerations[connectionString] = (_poolGenerations[connectionString] ?? 0) + 1;
  }
}

final class _CachedPoolState {
  const _CachedPoolState(this.state, this.capturedAt);

  final PoolState state;
  final DateTime capturedAt;
}
