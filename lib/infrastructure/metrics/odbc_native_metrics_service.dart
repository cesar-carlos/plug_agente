import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

/// Collects native diagnostics snapshots from `odbc_fast`.
class OdbcNativeMetricsService {
  OdbcNativeMetricsService(
    this._service, {
    IAgentConfigRepository? configRepository,
    IConnectionPool? connectionPool,
    IOdbcConnectionSettings? settings,
  }) : _configRepository = configRepository,
       _connectionPool = connectionPool,
       _settings = settings;

  final OdbcService _service;
  final IAgentConfigRepository? _configRepository;
  final IConnectionPool? _connectionPool;
  final IOdbcConnectionSettings? _settings;

  Future<Result<Map<String, dynamic>>> collectSnapshot() async {
    final metricsResult = await _service.getMetrics();
    if (metricsResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          metricsResult.exceptionOrNull()!,
          operation: 'odbc_get_metrics',
        ),
      );
    }

    final preparedResult = await _service.getPreparedStatementsMetrics();
    if (preparedResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          preparedResult.exceptionOrNull()!,
          operation: 'odbc_get_prepared_metrics',
        ),
      );
    }

    final metrics = metricsResult.getOrThrow();
    final prepared = preparedResult.getOrThrow();
    final resolvedConnectionString = await _resolveConnectionString();
    final validationSnapshot = await _collectValidationSnapshot(
      resolvedConnectionString,
    );
    final capabilitiesSnapshot = await _collectCapabilitiesSnapshot(
      resolvedConnectionString,
    );
    final nativePoolSnapshot = await _collectNativePoolSnapshot(
      resolvedConnectionString,
    );

    return Success(<String, dynamic>{
      'engine': <String, dynamic>{
        'query_count': metrics.queryCount,
        'error_count': metrics.errorCount,
        'uptime_secs': metrics.uptimeSecs,
        'total_latency_millis': metrics.totalLatencyMillis,
        'avg_latency_millis': metrics.avgLatencyMillis,
      },
      'prepared_statements': <String, dynamic>{
        'cache_size': prepared.cacheSize,
        'cache_max_size': prepared.cacheMaxSize,
        'cache_hits': prepared.cacheHits,
        'cache_misses': prepared.cacheMisses,
        'total_prepares': prepared.totalPrepares,
        'total_executions': prepared.totalExecutions,
        'memory_usage_bytes': prepared.memoryUsageBytes,
        'avg_executions_per_stmt': prepared.avgExecutionsPerStmt,
        'cache_hit_rate': prepared.cacheHitRate,
        'cache_miss_rate': prepared.cacheMissRate,
        'cache_utilization': prepared.cacheUtilization,
      },
      'connection': validationSnapshot,
      'driver_capabilities': capabilitiesSnapshot,
      'native_pool': nativePoolSnapshot,
    });
  }

  Future<String?> _resolveConnectionString() async {
    final repository = _configRepository;
    if (repository == null) {
      return null;
    }

    final configResult = await repository.getCurrentConfig();
    return configResult.fold(
      (config) {
        final resolved = config.resolveConnectionString().trim();
        return resolved.isEmpty ? null : resolved;
      },
      (_) => null,
    );
  }

  Future<Map<String, dynamic>> _collectValidationSnapshot(
    String? connectionString,
  ) async {
    if (connectionString == null) {
      return const <String, dynamic>{'available': false};
    }

    final validationResult = await _service.validateConnectionString(
      connectionString,
    );
    return validationResult.fold(
      (_) => const <String, dynamic>{
        'available': true,
        'valid': true,
      },
      (error) => <String, dynamic>{
        'available': true,
        'valid': false,
        'error': error.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> _collectCapabilitiesSnapshot(
    String? connectionString,
  ) async {
    if (connectionString == null) {
      return const <String, dynamic>{'available': false};
    }

    final capabilitiesResult = await _service.getDriverCapabilities(
      connectionString,
    );
    return capabilitiesResult.fold(
      (capabilities) => <String, dynamic>{
        'available': true,
        ...capabilities,
      },
      (error) => <String, dynamic>{
        'available': false,
        'error': error.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> _collectNativePoolSnapshot(
    String? connectionString,
  ) async {
    if (connectionString == null || _settings?.useNativeOdbcPool != true) {
      return const <String, dynamic>{'available': false};
    }

    final pool = _connectionPool;
    if (pool is! OdbcNativeConnectionPool) {
      return const <String, dynamic>{'available': false};
    }

    final stateResult = await pool.getDetailedState(connectionString);
    return stateResult.fold(
      (state) => <String, dynamic>{...state},
      (error) => <String, dynamic>{
        'available': false,
        'error': error.toString(),
      },
    );
  }
}
