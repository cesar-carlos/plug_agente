import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';

final class PoolHealthSnapshot {
  const PoolHealthSnapshot({
    required this.diagnostics,
    required this.capturedAt,
    this.activeCount,
  });

  final int? activeCount;
  final Map<String, Object?> diagnostics;
  final DateTime capturedAt;
}

final class PoolHealthResolver {
  PoolHealthResolver({
    IConnectionPool? connectionPool,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    Duration poolSnapshotTtl = const Duration(seconds: 2),
  }) : _connectionPool = connectionPool,
       _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _poolSnapshotTtl = poolSnapshotTtl;

  final IConnectionPool? _connectionPool;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final Duration _poolSnapshotTtl;

  Future<String?>? _driverTypeResolution;
  String? _cachedDriverType;
  Future<PoolHealthSnapshot>? _poolSnapshotResolution;
  PoolHealthSnapshot? _cachedPoolSnapshot;

  IConnectionPool? get connectionPool => _connectionPool;

  Future<void> reconcilePoolDiscardInflight(IPoolDiscardInflightDiagnostics? diagnostics) async {
    await diagnostics?.reconcilePoolDiscardInflight();
  }

  Future<PoolHealthSnapshot> resolvePoolSnapshot() => _resolvePoolSnapshot(_connectionPool);

  Future<String?> resolveDriverType({Map<String, Object?> poolDiagnostics = const {}}) async {
    final fromDiagnostics = poolDiagnostics['driver_type'] as String?;
    if (fromDiagnostics != null) {
      return fromDiagnostics;
    }
    return _resolveDriverType();
  }

  Future<PoolHealthSnapshot> _resolvePoolSnapshot(IConnectionPool? pool) async {
    final cached = _cachedPoolSnapshot;
    if (cached != null && DateTime.now().difference(cached.capturedAt) < _poolSnapshotTtl) {
      return cached;
    }

    final inFlight = _poolSnapshotResolution;
    if (inFlight != null) {
      return inFlight;
    }

    final resolution = _loadPoolSnapshot(pool);
    _poolSnapshotResolution = resolution;
    try {
      final snapshot = await resolution;
      _cachedPoolSnapshot = snapshot;
      return snapshot;
    } finally {
      _poolSnapshotResolution = null;
    }
  }

  Future<PoolHealthSnapshot> _loadPoolSnapshot(IConnectionPool? pool) async {
    final diagnostics = switch (pool) {
      final IConnectionPoolDiagnostics diagnosticsPool => diagnosticsPool.getHealthDiagnostics(),
      _ => const <String, Object?>{},
    };

    if (pool == null) {
      return PoolHealthSnapshot(
        diagnostics: diagnostics,
        capturedAt: DateTime.now(),
      );
    }

    final activeCountResult = await pool.getActiveCount();
    return PoolHealthSnapshot(
      activeCount: activeCountResult.getOrNull(),
      diagnostics: diagnostics,
      capturedAt: DateTime.now(),
    );
  }

  Future<String?> _resolveDriverType() async {
    final cachedDriverType = _cachedDriverType;
    if (cachedDriverType != null) {
      return cachedDriverType;
    }

    final inFlightResolution = _driverTypeResolution;
    if (inFlightResolution != null) {
      return inFlightResolution;
    }

    final resolution = _loadDriverType();
    _driverTypeResolution = resolution;
    try {
      final driverType = await resolution;
      if (driverType != null) {
        _cachedDriverType = driverType;
      }
      return driverType;
    } finally {
      _driverTypeResolution = null;
    }
  }

  Future<String?> _loadDriverType() async {
    final resolver = _activeConfigResolver;
    if (resolver == null && _configRepository == null) {
      return null;
    }

    final configResult = resolver != null
        ? await resolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await _configRepository!.getCurrentConfigMetadata();
    return configResult.fold(
      (config) => switch (DatabaseDriver.fromString(config.driverName)) {
        DatabaseDriver.sqlServer => 'sqlServer',
        DatabaseDriver.postgreSQL => 'postgresql',
        DatabaseDriver.sqlAnywhere => 'sybaseAnywhere',
        DatabaseDriver.unknown => null,
      },
      (_) => null,
    );
  }
}
