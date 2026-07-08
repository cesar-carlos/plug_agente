import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart' as app_db;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

enum _AdaptivePoolOwner { lease, native }

/// Routes eligible drivers to the experimental native pool while keeping the
/// lease-based pool as the baseline and fallback path.
final class AdaptiveOdbcConnectionPool
    implements
        IConnectionPool,
        ITimedConnectionPoolAcquire,
        INativeCompatibleConnectionPoolAcquire,
        IConnectionPoolDiagnostics,
        IConnectionPoolWarmUp,
        IAdaptivePoolFeedback {
  AdaptiveOdbcConnectionPool({
    required OdbcConnectionPool leasePool,
    required OdbcNativeConnectionPool nativePool,
    required FeatureFlags featureFlags,
    required MetricsCollector metricsCollector,
    IQueryConfigSource? queryConfigSource,
    IAgentConfigRepository? configRepository,
    Duration nativeCircuitBreakDuration = const Duration(minutes: 1),
    int nativeCircuitBreakThreshold = 3,
    int nativeWarmUpCount = 1,
    bool nativeWarmUpEnabled = ConnectionConstants.defaultNativeWarmUpEnabled,
    Duration driverInfoCacheTtl = const Duration(seconds: 10),
  }) : _leasePool = leasePool,
       _nativePool = nativePool,
       _featureFlags = featureFlags,
       _metrics = metricsCollector,
       _queryConfigSource = queryConfigSource,
       _configRepository = configRepository,
       _nativeCircuitBreakDuration = nativeCircuitBreakDuration,
       _nativeCircuitBreakThreshold = nativeCircuitBreakThreshold,
       _nativeWarmUpCount = nativeWarmUpCount,
       _nativeWarmUpEnabled = nativeWarmUpEnabled,
       _driverInfoCacheTtl = driverInfoCacheTtl;

  final OdbcConnectionPool _leasePool;
  final OdbcNativeConnectionPool _nativePool;

  /// Native pool used for pool-scoped bulk insert operations.
  OdbcNativeConnectionPool get nativeBulkInsertPool => _nativePool;
  final FeatureFlags _featureFlags;
  final MetricsCollector _metrics;
  final IQueryConfigSource? _queryConfigSource;
  final IAgentConfigRepository? _configRepository;
  final Duration _nativeCircuitBreakDuration;
  final int _nativeCircuitBreakThreshold;
  final int _nativeWarmUpCount;
  final bool _nativeWarmUpEnabled;
  final Map<String, _AdaptivePoolOwner> _connectionOwners = <String, _AdaptivePoolOwner>{};
  final Map<String, String> _connectionCircuitKeys = <String, String>{};
  final Map<String, String> _connectionAcquireStrings = <String, String>{};
  final Set<String> _pendingRecycleConnectionStrings = <String>{};
  bool _recyclePoolsWhenOwnersDrain = false;
  final Map<String, _NativeCircuitState> _nativeCircuits = <String, _NativeCircuitState>{};
  Future<_AdaptiveDriverInfo?>? _driverInfoFuture;
  _AdaptiveDriverInfo? _driverInfo;
  DateTime? _driverInfoLoadedAt;
  String? _lastEffectiveStrategy;
  String? _lastCircuitKey;
  String? _lastNativeSkipReason;
  int _nativeExecutionFallbackCount = 0;
  int _leaseActiveCount = 0;
  int _nativeActiveCount = 0;
  final Duration _driverInfoCacheTtl;

  @override
  Future<Result<String>> acquire(
    String connectionString, {
    ConnectionAcquireOptions? options,
  }) {
    return acquireWithin(
      connectionString,
      options: options,
    );
  }

  @override
  Future<Result<String>> acquireWithin(
    String connectionString, {
    ConnectionAcquireOptions? options,
    Duration? acquireTimeout,
  }) async {
    return _acquireWithStrategy(
      connectionString,
      options: options,
      leaseFallbackOptions: options,
      acquireTimeout: acquireTimeout,
      allowNativeWithoutOptions: false,
    );
  }

  @override
  Future<Result<String>> acquireNativeCompatible(
    String connectionString, {
    required ConnectionAcquireOptions leaseFallbackOptions,
    Duration? acquireTimeout,
  }) {
    _metrics.recordOdbcNativeCompatibleAcquireAttempt();
    return _acquireWithStrategy(
      connectionString,
      leaseFallbackOptions: leaseFallbackOptions,
      acquireTimeout: acquireTimeout,
      allowNativeWithoutOptions: true,
    );
  }

  Future<Result<String>> _acquireWithStrategy(
    String connectionString, {
    required ConnectionAcquireOptions? leaseFallbackOptions,
    required bool allowNativeWithoutOptions,
    ConnectionAcquireOptions? options,
    Duration? acquireTimeout,
  }) async {
    final driverInfo = await _resolveDriverInfo();
    final databaseType = driverInfo?.databaseType;
    final circuitKey = _nativeCircuitKey(
      connectionString: connectionString,
      driverInfo: driverInfo,
    );
    _lastCircuitKey = circuitKey;
    final canTryNativeWithoutOptions = allowNativeWithoutOptions || options == null;
    if (_shouldUseNativePool(databaseType) && !_isNativeCircuitOpen(circuitKey) && canTryNativeWithoutOptions) {
      final nativeAcquire = await _nativePool.acquireWithin(
        connectionString,
        acquireTimeout: acquireTimeout,
      );
      if (nativeAcquire.isSuccess()) {
        final connectionId = nativeAcquire.getOrThrow();
        _connectionOwners[connectionId] = _AdaptivePoolOwner.native;
        _connectionCircuitKeys[connectionId] = circuitKey;
        _connectionAcquireStrings[connectionId] = connectionString;
        _nativeActiveCount++;
        _lastEffectiveStrategy = allowNativeWithoutOptions ? 'native_compatible' : 'native';
        _recordNativeSuccess(circuitKey);
        if (allowNativeWithoutOptions) {
          _metrics.recordOdbcNativeCompatibleAcquireSuccess();
        }
        return Success(connectionId);
      }

      final nativeError = nativeAcquire.exceptionOrNull();
      if (!_shouldFallbackToLease(nativeError)) {
        return Failure(nativeError!);
      }

      _metrics.recordOdbcNativePoolFallback();
      _recordNativeFallback(circuitKey);
    }

    if (_shouldUseNativePool(databaseType)) {
      if (!canTryNativeWithoutOptions) {
        _lastNativeSkipReason = OdbcContextConstants.nativePoolCustomOptionsUnsupportedReason;
      } else if (allowNativeWithoutOptions) {
        _lastNativeSkipReason ??= _isNativeCircuitOpen(circuitKey) ? 'native_circuit_open' : 'native_fallback_to_lease';
      }
    }

    final leaseAcquire = await _leasePool.acquireWithin(
      connectionString,
      options: leaseFallbackOptions ?? options,
      acquireTimeout: acquireTimeout,
    );
    if (leaseAcquire.isSuccess()) {
      final connectionId = leaseAcquire.getOrThrow();
      _connectionOwners[connectionId] = _AdaptivePoolOwner.lease;
      _connectionCircuitKeys.remove(connectionId);
      _connectionAcquireStrings[connectionId] = connectionString;
      _leaseActiveCount++;
      _lastEffectiveStrategy = 'lease';
      return Success(connectionId);
    }

    return Failure(leaseAcquire.exceptionOrNull()!);
  }

  @override
  void recordExecutionFailure({
    required String connectionString,
    required Object error,
    String? connectionId,
    String? stage,
  }) {
    final owner = connectionId == null ? null : _connectionOwners[connectionId];
    if (owner != _AdaptivePoolOwner.native || !_shouldFallbackToLease(error)) {
      return;
    }

    final circuitKey = _circuitKeyForExecutionFailure(
      connectionString: connectionString,
      connectionId: connectionId,
    );
    _lastCircuitKey = circuitKey;
    _lastEffectiveStrategy = 'lease';
    _nativeExecutionFallbackCount++;
    _metrics.recordOdbcNativePoolFallback();
    _recordNativeFallback(circuitKey);
  }

  @override
  Future<Result<void>> warmUp(
    String connectionString, {
    int? warmUpCount,
  }) async {
    final driverInfo = await _resolveDriverInfo();
    final circuitKey = _nativeCircuitKey(
      connectionString: connectionString,
      driverInfo: driverInfo,
    );
    _lastCircuitKey = circuitKey;

    if (!_nativeWarmUpEnabled || !_shouldUseNativePool(driverInfo?.databaseType) || _isNativeCircuitOpen(circuitKey)) {
      if (!_nativeWarmUpEnabled && _shouldUseNativePool(driverInfo?.databaseType)) {
        _lastNativeSkipReason = 'native_warmup_disabled';
        _lastEffectiveStrategy = 'lease';
      }
      return _leasePool.warmUp(
        connectionString,
        warmUpCount: warmUpCount,
      );
    }

    final result = await _nativePool.warmUp(
      connectionString,
      warmUpCount: warmUpCount ?? _nativeWarmUpCount,
    );
    if (result.isSuccess()) {
      _recordNativeSuccess(circuitKey);
      return result;
    }

    final error = result.exceptionOrNull();
    if (!_shouldFallbackToLease(error)) {
      return Failure(error!);
    }

    _metrics.recordOdbcNativePoolFallback();
    _recordNativeFallback(circuitKey);
    return _leasePool.warmUp(
      connectionString,
      warmUpCount: warmUpCount,
    );
  }

  @override
  Future<Result<void>> release(String connectionId) async {
    final owner = _connectionOwners.remove(connectionId);
    _connectionCircuitKeys.remove(connectionId);
    _connectionAcquireStrings.remove(connectionId);
    _decrementOwnerActiveCount(owner);
    final result = await _releaseToOwnerPool(connectionId, owner);
    await _maybeCompleteConfigDrain();
    return result;
  }

  @override
  Future<Result<void>> discard(String connectionId) async {
    final owner = _connectionOwners.remove(connectionId);
    _connectionCircuitKeys.remove(connectionId);
    _connectionAcquireStrings.remove(connectionId);
    _decrementOwnerActiveCount(owner);
    final result = await _discardFromOwnerPool(connectionId, owner);
    await _maybeCompleteConfigDrain();
    return result;
  }

  Future<Result<void>> _releaseToOwnerPool(
    String connectionId,
    _AdaptivePoolOwner? owner,
  ) async {
    if (owner == null) {
      // Unknown owner: the ID may belong to the native pool if owner tracking
      // was lost (e.g. double-release). Routing blindly to the lease pool would
      // call disconnect() instead of poolReleaseConnection(), leaving the native
      // pool slot permanently occupied. Route by checking lease-pool tracking.
      developer.log(
        'release called for connection with no tracked owner: $connectionId',
        name: 'adaptive_odbc_connection_pool',
        level: 900,
      );
      final activeCountResult = await _leasePool.getActiveCount();
      final knownToLeasePool = activeCountResult.isSuccess() && _leasePool.isTracked(connectionId);
      return knownToLeasePool ? _leasePool.release(connectionId) : _nativePool.release(connectionId);
    }
    return switch (owner) {
      _AdaptivePoolOwner.native => _nativePool.release(connectionId),
      _AdaptivePoolOwner.lease => _leasePool.release(connectionId),
    };
  }

  Future<Result<void>> _discardFromOwnerPool(
    String connectionId,
    _AdaptivePoolOwner? owner,
  ) async {
    if (owner == null) {
      developer.log(
        'discard called for connection with no tracked owner: $connectionId',
        name: 'adaptive_odbc_connection_pool',
        level: 900,
      );
      return _leasePool.isTracked(connectionId) ? _leasePool.discard(connectionId) : _nativePool.discard(connectionId);
    }
    return switch (owner) {
      _AdaptivePoolOwner.native => _nativePool.discard(connectionId),
      _AdaptivePoolOwner.lease => _leasePool.discard(connectionId),
    };
  }

  @override
  Future<Result<void>> closeAll() async {
    final errors = <Object>[];
    final nativeResult = await _nativePool.closeAll();
    if (nativeResult.isError()) {
      errors.add(nativeResult.exceptionOrNull()!);
    }

    final leaseResult = await _leasePool.closeAll();
    if (leaseResult.isError()) {
      errors.add(leaseResult.exceptionOrNull()!);
    }

    _connectionOwners.clear();
    _connectionCircuitKeys.clear();
    _connectionAcquireStrings.clear();
    _pendingRecycleConnectionStrings.clear();
    _recyclePoolsWhenOwnersDrain = false;
    _leaseActiveCount = 0;
    _nativeActiveCount = 0;
    if (errors.isNotEmpty) {
      return Failure(_aggregatePoolFailure(errors, operation: 'pool_close_all'));
    }

    return const Success(unit);
  }

  void _decrementOwnerActiveCount(_AdaptivePoolOwner? owner) {
    switch (owner) {
      case _AdaptivePoolOwner.lease:
        if (_leaseActiveCount > 0) {
          _leaseActiveCount--;
        }
      case _AdaptivePoolOwner.native:
        if (_nativeActiveCount > 0) {
          _nativeActiveCount--;
        }
      case null:
        break;
    }
  }

  @override
  Future<Result<void>> recycle(String connectionString) async {
    final errors = <Object>[];
    final nativeResult = await _nativePool.recycle(connectionString);
    if (nativeResult.isError()) {
      errors.add(nativeResult.exceptionOrNull()!);
    }

    final leaseResult = await _leasePool.recycle(connectionString);
    if (leaseResult.isError()) {
      errors.add(leaseResult.exceptionOrNull()!);
    }

    if (errors.isNotEmpty) {
      return Failure(_aggregatePoolFailure(errors, operation: 'pool_recycle'));
    }

    return const Success(unit);
  }

  /// Preserves typed child failures (with their `cause`/`context`) instead of
  /// flattening them into a raw `Exception` string. A single child failure is
  /// returned as-is; multiple are aggregated under a typed failure that keeps
  /// the first as `cause`.
  domain.Failure _aggregatePoolFailure(
    List<Object> errors, {
    required String operation,
  }) {
    if (errors.length == 1 && errors.first is domain.Failure) {
      return errors.first as domain.Failure;
    }

    final messages = errors.map((error) => error is domain.Failure ? error.message : error.toString()).join('; ');
    return domain.ConnectionFailure.withContext(
      message: 'Pool operation completed with errors: $messages',
      cause: errors.first,
      context: {
        'reason': OdbcContextConstants.poolErrorReason,
        'operation': operation,
        'error_count': errors.length,
      },
    );
  }

  @override
  Future<Result<int>> getActiveCount({String? connectionString}) async {
    final nativeResult = await _nativePool.getActiveCount(
      connectionString: connectionString,
    );
    if (nativeResult.isError()) {
      return Failure(nativeResult.exceptionOrNull()!);
    }

    final leaseResult = await _leasePool.getActiveCount(
      connectionString: connectionString,
    );
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }

    return Success(nativeResult.getOrThrow() + leaseResult.getOrThrow());
  }

  Future<void> _reconcileActiveCounts() async {
    final nativeResult = await _nativePool.getActiveCount();
    if (nativeResult.isSuccess()) {
      _nativeActiveCount = nativeResult.getOrThrow();
    }

    final leaseResult = await _leasePool.getActiveCount();
    if (leaseResult.isSuccess()) {
      _leaseActiveCount = leaseResult.getOrThrow();
    }
  }

  @override
  Future<Result<void>> healthCheckAll() async {
    await _reconcileActiveCounts();

    final errors = <Object>[];
    final nativeResult = await _nativePool.healthCheckAll();
    if (nativeResult.isError()) {
      errors.add(nativeResult.exceptionOrNull()!);
    }

    final leaseResult = await _leasePool.healthCheckAll();
    if (leaseResult.isError()) {
      errors.add(leaseResult.exceptionOrNull()!);
    }

    if (errors.isNotEmpty) {
      return Failure(_aggregatePoolFailure(errors, operation: 'pool_health_check'));
    }

    return const Success(unit);
  }

  bool _shouldUseNativePool(app_db.DatabaseType? databaseType) {
    if (!_featureFlags.enableOdbcExperimentalDriverAdaptivePooling || databaseType == null) {
      return false;
    }

    return _isNativeEligible(databaseType);
  }

  bool _isNativeEligible(app_db.DatabaseType databaseType) {
    return switch (databaseType) {
      app_db.DatabaseType.sqlServer => true,
      app_db.DatabaseType.postgresql => true,
      app_db.DatabaseType.sybaseAnywhere => false,
    };
  }

  bool _shouldFallbackToLease(Object? error) {
    if (error == null) {
      return false;
    }

    return OdbcErrorInspector.isInvalidConnectionId(error) ||
        OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
          OdbcErrorInspector.message(error),
        ) ||
        OdbcErrorInspector.isTimeout(error) ||
        _hasFailureReason(error, 'buffer_too_small') ||
        _hasFailureReason(error, OdbcContextConstants.odbcWorkerBusyConnectReason) ||
        _looksLikePoolHealthFailure(error);
  }

  String _nativeCircuitKey({
    required String connectionString,
    required _AdaptiveDriverInfo? driverInfo,
  }) {
    return '${driverInfo?.driverType ?? 'unknown'}:${_shortStableHash(connectionString)}';
  }

  bool _isNativeCircuitOpen(String key) {
    final state = _nativeCircuits[key];
    if (state?.disabledUntil case final disabledUntil?) {
      if (DateTime.now().isBefore(disabledUntil)) {
        _lastEffectiveStrategy = 'lease';
        return true;
      }

      _nativeCircuits.remove(key);
      return false;
    }

    return false;
  }

  void _recordNativeSuccess(String key) {
    _nativeCircuits.remove(key);
  }

  void _recordNativeFallback(String key) {
    final current = _nativeCircuits[key] ?? const _NativeCircuitState();
    final failures = current.failures + 1;
    final disabledUntil = failures >= _nativeCircuitBreakThreshold
        ? DateTime.now().add(_nativeCircuitBreakDuration)
        : null;
    final reason = disabledUntil == null ? 'native_fallback' : 'native_circuit_open';
    _metrics.recordOdbcNativeFallback(reason);
    if (disabledUntil != null) {
      _metrics.recordOdbcNativeCircuitOpened();
    }
    _metrics.recordDiagnosticReason(
      category: 'pool',
      reason: reason,
    );
    _nativeCircuits[key] = _NativeCircuitState(
      failures: failures,
      disabledUntil: disabledUntil,
    );
  }

  bool _hasFailureReason(Object error, String reason) {
    if (error is! domain.Failure) {
      return false;
    }

    if (error.context['reason'] == reason) {
      return true;
    }

    final cause = error.cause;
    if (cause is domain.Failure) {
      return _hasFailureReason(cause, reason);
    }

    return false;
  }

  bool _looksLikePoolHealthFailure(Object error) {
    if (error is domain.Failure && error.context['operation'] == 'pool_health_check') {
      return true;
    }

    final message = OdbcErrorInspector.message(error).toLowerCase();
    return message.contains('pool') && message.contains('unhealthy');
  }

  String _circuitKeyForExecutionFailure({
    required String connectionString,
    required String? connectionId,
  }) {
    final mappedKey = connectionId == null ? null : _connectionCircuitKeys[connectionId];
    if (mappedKey != null) {
      return mappedKey;
    }

    return _nativeCircuitKey(
      connectionString: connectionString,
      driverInfo: _driverInfo,
    );
  }

  Future<_AdaptiveDriverInfo?> _resolveDriverInfo() async {
    final cached = _driverInfo;
    final loadedAt = _driverInfoLoadedAt;
    if (cached != null && loadedAt != null && DateTime.now().difference(loadedAt) < _driverInfoCacheTtl) {
      return cached;
    }

    final inFlight = _driverInfoFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final resolution = _loadDriverInfo();
    _driverInfoFuture = resolution;
    try {
      final resolved = await resolution;
      final current = _driverInfo;
      if (resolved == null) {
        _driverInfo = null;
        _driverInfoLoadedAt = null;
        _lastCircuitKey = null;
        return null;
      }
      if (current != null && current.cacheKey != resolved.cacheKey) {
        _nativeCircuits.clear();
        if (_connectionOwners.isNotEmpty) {
          _markConfigDrainPending();
        } else {
          _connectionCircuitKeys.clear();
          _lastCircuitKey = null;
        }
      }
      _driverInfo = resolved;
      _driverInfoLoadedAt = DateTime.now();
      return resolved;
    } finally {
      _driverInfoFuture = null;
    }
  }

  Future<_AdaptiveDriverInfo?> _loadDriverInfo() async {
    final queryConfigSource = _queryConfigSource;
    if (queryConfigSource == null && _configRepository == null) {
      return null;
    }

    final configResult = queryConfigSource != null
        ? await queryConfigSource.resolveActiveConfig()
        : await _configRepository!.getCurrentConfigMetadata();
    return configResult.fold(
      (config) {
        final databaseType = _mapDriverNameToDatabaseType(config.driverName);
        if (databaseType == null) {
          return null;
        }

        return _AdaptiveDriverInfo(
          databaseType: databaseType,
          driverType: _driverTypeName(databaseType),
          cacheKey: _configCacheKey(config),
        );
      },
      (_) => null,
    );
  }

  String _configCacheKey(Config config) {
    return [
      config.id,
      config.driverName,
      config.odbcDriverName,
      _shortStableHash(config.connectionString),
    ].join('|');
  }

  String _shortStableHash(String value) {
    return sha256.convert(utf8.encode(value)).toString().substring(0, 16);
  }

  app_db.DatabaseType? _mapDriverNameToDatabaseType(String driverName) {
    return switch (DatabaseDriver.fromString(driverName)) {
      DatabaseDriver.sqlServer => app_db.DatabaseType.sqlServer,
      DatabaseDriver.postgreSQL => app_db.DatabaseType.postgresql,
      DatabaseDriver.sqlAnywhere => app_db.DatabaseType.sybaseAnywhere,
      DatabaseDriver.unknown => null,
    };
  }

  String _driverTypeName(app_db.DatabaseType databaseType) {
    return switch (databaseType) {
      app_db.DatabaseType.sqlServer => 'sqlServer',
      app_db.DatabaseType.postgresql => 'postgresql',
      app_db.DatabaseType.sybaseAnywhere => 'sybaseAnywhere',
    };
  }

  @override
  Map<String, Object?> getHealthDiagnostics() {
    final resolvedDriverInfo = _driverInfo;
    final nativeEligible = resolvedDriverInfo == null ? null : _isNativeEligible(resolvedDriverInfo.databaseType);
    final circuitState = _lastCircuitKey == null ? null : _nativeCircuits[_lastCircuitKey];
    final circuitDisabledUntil = circuitState?.disabledUntil;
    return {
      'strategy': 'adaptive_experimental',
      'effective_strategy': _lastEffectiveStrategy ?? 'lease',
      'native_pool_exposed': _featureFlags.enableOdbcExperimentalDriverAdaptivePooling,
      'experimental_enabled': _featureFlags.enableOdbcExperimentalDriverAdaptivePooling,
      'native_eligible': nativeEligible,
      'native_circuit_open': circuitDisabledUntil != null && DateTime.now().isBefore(circuitDisabledUntil),
      'native_circuit_failures': circuitState?.failures ?? 0,
      'native_circuit_disabled_until': circuitDisabledUntil?.toIso8601String(),
      'native_execution_fallback_total': _nativeExecutionFallbackCount,
      'native_compatible_acquire_attempt_total': _metrics.odbcNativeCompatibleAcquireAttemptCount,
      'native_compatible_acquire_success_total': _metrics.odbcNativeCompatibleAcquireSuccessCount,
      'native_skip_reason': _lastNativeSkipReason,
      'native_warmup_enabled': _nativeWarmUpEnabled,
      'driver_type': resolvedDriverInfo?.driverType,
      'lease_active_count': _leaseActiveCount,
      'native_active_count': _nativeActiveCount,
      'config_drain_pending': _recyclePoolsWhenOwnersDrain,
      'tracked_owner_count': _connectionOwners.length,
    };
  }

  void _markConfigDrainPending() {
    _recyclePoolsWhenOwnersDrain = true;
    for (final connectionId in _connectionOwners.keys) {
      final connectionString = _connectionAcquireStrings[connectionId];
      if (connectionString != null) {
        _pendingRecycleConnectionStrings.add(connectionString);
      }
    }
  }

  Future<void> _maybeCompleteConfigDrain() async {
    if (!_recyclePoolsWhenOwnersDrain || _connectionOwners.isNotEmpty) {
      return;
    }

    _recyclePoolsWhenOwnersDrain = false;
    _connectionCircuitKeys.clear();
    _lastCircuitKey = null;

    final connectionStrings = _pendingRecycleConnectionStrings.toList(growable: false);
    _pendingRecycleConnectionStrings.clear();
    if (connectionStrings.isEmpty) {
      return;
    }

    final errors = <Object>[];
    for (final connectionString in connectionStrings) {
      final recycleResult = await recycle(connectionString);
      if (recycleResult.isError()) {
        errors.add(recycleResult.exceptionOrNull()!);
      }
    }

    if (errors.isNotEmpty) {
      developer.log(
        'Adaptive pool config drain recycle completed with errors',
        name: 'adaptive_odbc_connection_pool',
        level: 900,
        error: errors,
      );
    }
  }
}

final class _AdaptiveDriverInfo {
  const _AdaptiveDriverInfo({
    required this.databaseType,
    required this.driverType,
    required this.cacheKey,
  });

  final app_db.DatabaseType databaseType;
  final String driverType;
  final String cacheKey;
}

final class _NativeCircuitState {
  const _NativeCircuitState({
    this.failures = 0,
    this.disabledUntil,
  });

  final int failures;
  final DateTime? disabledUntil;
}
