import 'dart:developer' as developer;

import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/odbc_runtime_helpers.dart' show resolveOdbcRuntimeTuning;
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_application_runtime_reset_port.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_runtime_reload_teardown_port.dart';
import 'package:plug_agente/domain/repositories/i_odbc_runtime_reloader.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/cache/odbc_connection_string_ttl_cache.dart';
import 'package:plug_agente/infrastructure/config/odbc_metadata_cache_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_performance_preset_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';

/// Reloads ODBC-facing singletons after persisted connection settings change.
final class OdbcRuntimeReloader implements IOdbcRuntimeReloader {
  OdbcRuntimeReloader({
    required GetIt getIt,
    required odbc.ServiceLocator odbcWorkerLocator,
    required IOdbcApplicationRuntimeResetPort applicationRuntimeResetPort,
    required IOdbcRuntimeReloadTeardownPort teardownPort,
  }) : _getIt = getIt,
       _odbcWorkerLocator = odbcWorkerLocator,
       _applicationRuntimeResetPort = applicationRuntimeResetPort,
       _teardownPort = teardownPort;

  final GetIt _getIt;
  final odbc.ServiceLocator _odbcWorkerLocator;
  final IOdbcApplicationRuntimeResetPort _applicationRuntimeResetPort;
  final IOdbcRuntimeReloadTeardownPort _teardownPort;

  @override
  Future<bool> reload() async {
    var agentActionsMarkedDraining = false;
    try {
      if (_getIt.isRegistered<OdbcConnectionStringTtlCache>()) {
        _getIt<OdbcConnectionStringTtlCache>().invalidate();
      }

      agentActionsMarkedDraining = _teardownPort.markAgentActionsDraining();

      if (_getIt.isRegistered<ISqlInvestigationCollector>()) {
        _getIt<ISqlInvestigationCollector>().clear();
      }

      await _teardownPort.disposeSqlExecutionQueue();
      await _teardownPort.drainStreamingSessionCache();
      await _teardownPort.disconnectHubTransport();

      if (_getIt.isRegistered<IConnectionPool>()) {
        await _getIt<IConnectionPool>().closeAll();
      }

      if (_getIt.isRegistered<OdbcEventBridge>()) {
        await _getIt<OdbcEventBridge>().dispose();
      }

      await _resetLazySingletonIfRegistered<ITransportClient>();
      await _applicationRuntimeResetPort.resetForOdbcRuntimeReload();
      await _resetLazySingletonIfRegistered<OdbcNativeMetricsService>();
      await _resetLazySingletonIfRegistered<OdbcEventBridge>();
      await _resetLazySingletonIfRegistered<IStreamingDatabaseGateway>();
      await _resetLazySingletonIfRegistered<IDatabaseGateway>();
      await _resetLazySingletonIfRegistered<DirectOdbcConnectionLimiter>();
      await _resetLazySingletonIfRegistered<IConnectionPool>();

      final odbcSettings = _getIt<IOdbcConnectionSettings>();
      await odbcSettings.load();

      applyOdbcPerformancePresetFromEnvironment();

      final newTuning = resolveOdbcRuntimeTuning(settings: odbcSettings);
      if (_getIt.isRegistered<OdbcRuntimeTuning>()) {
        _getIt.unregister<OdbcRuntimeTuning>();
      }
      _getIt.registerSingleton<OdbcRuntimeTuning>(newTuning);
      _logOdbcRuntimeTuningWarnings(newTuning);

      _odbcWorkerLocator.shutdown();
      final odbcUsageProfile = resolveOdbcUsageProfile();
      _odbcWorkerLocator.initialize(
        profile: odbcUsageProfile,
        useAsync: true,
        asyncWorkerCount: newTuning.asyncWorkerCount,
        asyncMaxPendingRequests: newTuning.asyncMaxPendingRequests,
        asyncBackpressureMode: odbc.AsyncBackpressureMode.failFast,
      );
      if (_getIt.isRegistered<OdbcProfileRecommendedOptions>()) {
        _getIt.unregister<OdbcProfileRecommendedOptions>();
      }
      _getIt.registerSingleton<OdbcProfileRecommendedOptions>(
        OdbcProfileRecommendedOptions(
          connection: _odbcWorkerLocator.recommendedConnectionOptions,
          pool: _odbcWorkerLocator.recommendedPoolOptions,
        ),
      );

      await _primeReloadedOdbcRuntimeDependencies();
      if (agentActionsMarkedDraining) {
        _teardownPort.markAgentActionsReady();
      }
      return true;
    } on Object catch (error, stackTrace) {
      if (agentActionsMarkedDraining) {
        _teardownPort.markAgentActionsReady();
      }
      developer.log(
        'Failed to reload ODBC runtime dependencies',
        name: 'service_locator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _resetLazySingletonIfRegistered<T extends Object>() async {
    if (!_getIt.isRegistered<T>()) {
      return;
    }
    await _getIt.resetLazySingleton<T>();
  }

  Future<void> _primeReloadedOdbcRuntimeDependencies() async {
    final odbcInitResult = await _getIt<odbc.OdbcService>().initialize();
    odbcInitResult.fold(
      (_) {},
      (error) {
        throw StateError('ODBC initialization failed after reload: $error');
      },
    );
    await _enableOdbcMetadataCacheIfConfigured(_getIt<odbc.OdbcService>());

    _getIt<DirectOdbcConnectionLimiter>();
    _getIt<IConnectionPool>();
    _getIt<IStreamingDatabaseGateway>();
    _getIt<IDatabaseGateway>();
    _getIt<OdbcEventBridge>();
  }

  Future<void> _enableOdbcMetadataCacheIfConfigured(odbc.OdbcService service) async {
    if (!isOdbcMetadataCacheEnabled()) {
      return;
    }

    final result = await service.metadataCacheEnable(
      maxEntries: odbcMetadataCacheDefaultMaxEntries,
      ttlSeconds: odbcMetadataCacheDefaultTtlSeconds,
    );
    result.fold(
      (_) {
        developer.log(
          'ODBC metadata cache enabled '
          '(maxEntries: $odbcMetadataCacheDefaultMaxEntries, '
          'ttlSeconds: $odbcMetadataCacheDefaultTtlSeconds)',
          name: 'service_locator',
          level: 800,
        );
      },
      (error) {
        developer.log(
          'ODBC metadata cache enable skipped or unavailable',
          name: 'service_locator',
          level: 800,
          error: error,
        );
      },
    );
  }

  void _logOdbcRuntimeTuningWarnings(OdbcRuntimeTuning tuning) {
    final sqlQueueMaxWorkers = ConnectionConstants.sqlQueueMaxWorkersForPoolSize(
      tuning.poolSize,
    );
    if (sqlQueueMaxWorkers > tuning.poolSize) {
      developer.log(
        'SQL queue workers exceed ODBC pool size '
        '(poolSize: ${tuning.poolSize}, sqlQueueMaxWorkers: $sqlQueueMaxWorkers)',
        name: 'service_locator',
        level: 900,
      );
    }

    if (tuning.asyncMaxPendingRequests < sqlQueueMaxWorkers) {
      developer.log(
        'ODBC async pending limit is lower than SQL queue worker count — '
        'failFast may reject dispatched requests '
        '(asyncMaxPendingRequests: ${tuning.asyncMaxPendingRequests}, '
        'sqlQueueMaxWorkers: $sqlQueueMaxWorkers)',
        name: 'service_locator',
        level: 900,
      );
    }

    final sqlQueueMaxSize = ConnectionConstants.sqlQueueMaxSize;
    if (ConnectionConstants.isSqlQueueDepthAboveOdbcAsyncPending(
      sqlQueueMaxSize: sqlQueueMaxSize,
      asyncMaxPendingRequests: tuning.asyncMaxPendingRequests,
    )) {
      developer.log(
        'SQL queue max size exceeds ODBC async pending limit — '
        'queued requests may be rejected by failFast before workers drain '
        '(sqlQueueMaxSize: $sqlQueueMaxSize, '
        'asyncMaxPendingRequests: ${tuning.asyncMaxPendingRequests})',
        name: 'service_locator',
        level: 900,
      );
    }
  }
}
