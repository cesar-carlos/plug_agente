import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/bootstrap/bootstrap_dependency_registrar.dart';
import 'package:plug_agente/bootstrap/bootstrap_odbc_worker_locator.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/feature_flags_env_seeder.dart';
import 'package:plug_agente/core/config/feature_flags_performance_defaults_migrator.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/get_it.dart';
import 'package:plug_agente/core/di/odbc_runtime_helpers.dart';
import 'package:plug_agente/core/logging/error_logging_bootstrap.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/config/odbc_metadata_cache_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_performance_preset_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_key_resolver.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_payload_signing_key_store.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

PayloadSigningKeyStore _createPayloadSigningKeyStore() {
  try {
    return FlutterSecurePayloadSigningKeyStore();
  } on Object catch (error, stackTrace) {
    developer.log(
      'FlutterSecurePayloadSigningKeyStore init failed, payload signing keys will use environment only',
      name: 'bootstrap_service_locator',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    return const NoopPayloadSigningKeyStore();
  }
}

Future<void> _migrateLegacyUserPreferences(
  GlobalAppSettingsStore appSettings,
) async {
  try {
    final legacyPrefs = await SharedPreferences.getInstance();
    final keys = legacyPrefs.getKeys();
    if (keys.isEmpty) {
      return;
    }

    final legacyValues = <String, Object?>{};
    for (final key in keys) {
      legacyValues[key] = legacyPrefs.get(key);
    }

    final migratedCount = await appSettings.importMissingEntries(legacyValues);
    if (migratedCount > 0) {
      developer.log(
        'Migrated $migratedCount legacy user preferences to global store',
        name: 'bootstrap_service_locator',
        level: 800,
      );
    }
  } on Exception catch (e, stackTrace) {
    developer.log(
      'Failed to migrate legacy user preferences (continuing)',
      name: 'bootstrap_service_locator',
      level: 900,
      error: e,
      stackTrace: stackTrace,
    );
  }
}

void _logOdbcRuntimeTuningWarnings(OdbcRuntimeTuning tuning) {
  final sqlQueueMaxWorkers = ConnectionConstants.sqlQueueMaxWorkersForPoolSize(
    tuning.poolSize,
  );
  if (sqlQueueMaxWorkers > tuning.poolSize) {
    developer.log(
      'SQL queue workers exceed ODBC pool size '
      '(poolSize: ${tuning.poolSize}, sqlQueueMaxWorkers: $sqlQueueMaxWorkers)',
      name: 'bootstrap_service_locator',
      level: 900,
    );
  }

  if (tuning.asyncMaxPendingRequests < sqlQueueMaxWorkers) {
    developer.log(
      'ODBC async pending limit is lower than SQL queue worker count — '
      'failFast may reject dispatched requests '
      '(asyncMaxPendingRequests: ${tuning.asyncMaxPendingRequests}, '
      'sqlQueueMaxWorkers: $sqlQueueMaxWorkers)',
      name: 'bootstrap_service_locator',
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
      name: 'bootstrap_service_locator',
      level: 900,
    );
  }
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
        name: 'bootstrap_service_locator',
        level: 800,
      );
    },
    (error) {
      developer.log(
        'ODBC metadata cache enable skipped or unavailable',
        name: 'bootstrap_service_locator',
        level: 800,
        error: error,
      );
    },
  );
}

Never _throwGlobalStorageBootstrapError(
  GlobalStorageAccessException error,
) {
  throw GlobalStorageBootstrapException(
    attempts: error.attempts,
  );
}

Future<GlobalStorageContext> _resolveGlobalStorageContextOrThrow() async {
  try {
    return await GlobalStoragePathResolver.resolveContext(
      directoryAclBootstrap: GlobalStorageAclBootstrap(),
    );
  } on GlobalStorageAccessException catch (error, stackTrace) {
    developer.log(
      'Unable to resolve global storage context',
      name: 'bootstrap_service_locator',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _throwGlobalStorageBootstrapError(error);
  }
}

Future<void> setupDependencies({
  required RuntimeCapabilities capabilities,
  RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
}) async {
  developer.log(
    'Setting up dependencies with runtime mode: ${capabilities.mode.displayName}',
    name: 'bootstrap_service_locator',
    level: 800,
  );

  if (!capabilities.canRunCore) {
    throw StateError(
      'Cannot run application: ${capabilities.degradationReasons.join(", ")}',
    );
  }

  ensureIanaTimeZoneDataLoaded();

  getIt.registerSingleton<RuntimeCapabilities>(capabilities);
  getIt.registerSingleton<HubConnectionShutdownRegistry>(HubConnectionShutdownRegistry());
  if (runtimeDetectionDiagnostics != null) {
    getIt.registerSingleton<RuntimeDetectionDiagnostics>(
      runtimeDetectionDiagnostics,
    );
  }

  final globalStorageContext = await _resolveGlobalStorageContextOrThrow();
  getIt.registerSingleton<GlobalStorageContext>(globalStorageContext);
  await ErrorLoggingBootstrap.upgradeToAppStorage(globalStorageContext);
  await ErrorLoggingBootstrap.registerErrorTracker(
    dsn: AppEnvironment.get('SENTRY_DSN') ?? '',
    environment: AppEnvironment.get('APP_ENV') ?? 'development',
    release: AppEnvironment.get('APP_RELEASE') ?? '',
  );

  final appSettings = GlobalAppSettingsStore(
    filePath: globalStorageContext.settingsFilePath,
  );
  try {
    await appSettings.initialize();
  } on GlobalStorageAccessException catch (error, stackTrace) {
    developer.log(
      'Unable to initialize global settings storage',
      name: 'bootstrap_service_locator',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _throwGlobalStorageBootstrapError(error);
  }
  await _migrateLegacyUserPreferences(appSettings);
  await FeatureFlagsEnvSeeder.applyUnsetOverrides(appSettings);
  await FeatureFlagsPerformanceDefaultsMigrator.apply(appSettings);
  getIt.registerSingleton<IAppSettingsStore>(appSettings);

  final agentRuntimeIdentity = await AgentRuntimeIdentity.load(settings: appSettings);
  getIt.registerSingleton<AgentRuntimeIdentity>(agentRuntimeIdentity);

  final odbcSettings = OdbcConnectionSettings(appSettings);
  await odbcSettings.load();
  getIt.registerSingleton<IOdbcConnectionSettings>(odbcSettings);

  applyOdbcPerformancePresetFromEnvironment();

  final odbcRuntimeTuning = resolveOdbcRuntimeTuning(settings: odbcSettings);
  getIt.registerSingleton<OdbcRuntimeTuning>(odbcRuntimeTuning);
  _logOdbcRuntimeTuningWarnings(odbcRuntimeTuning);

  final odbcUsageProfile = resolveOdbcUsageProfile();
  odbcWorkerLocator.initialize(
    profile: odbcUsageProfile,
    useAsync: true,
    asyncWorkerCount: odbcRuntimeTuning.asyncWorkerCount,
    asyncMaxPendingRequests: odbcRuntimeTuning.asyncMaxPendingRequests,
    asyncBackpressureMode: odbc.AsyncBackpressureMode.failFast,
  );
  getIt.registerSingleton<OdbcProfileRecommendedOptions>(
    OdbcProfileRecommendedOptions(
      connection: odbcWorkerLocator.recommendedConnectionOptions,
      pool: odbcWorkerLocator.recommendedPoolOptions,
    ),
  );
  developer.log(
    'ODBC async worker pool configured '
    '(usageProfile: ${odbcUsageProfileConfigName(odbcUsageProfile)}, '
    'poolSize: ${odbcRuntimeTuning.poolSize}, '
    'workerCount: ${odbcRuntimeTuning.asyncWorkerCount}, '
    'maxPendingRequests: ${odbcRuntimeTuning.asyncMaxPendingRequests}, '
    'backpressureMode: ${odbcRuntimeTuning.asyncBackpressureMode})',
    name: 'bootstrap_service_locator',
    level: 800,
    error: odbcRuntimeTuning.toMap(),
  );

  final featureFlags = FeatureFlags(appSettings);
  getIt.registerSingleton<FeatureFlags>(featureFlags);

  final hubResilienceConfig = HubResilienceConfig(featureFlags);
  getIt.registerSingleton<HubResilienceConfig>(hubResilienceConfig);

  final payloadSigningKeyStore = _createPayloadSigningKeyStore();
  getIt.registerSingleton<PayloadSigningKeyStore>(payloadSigningKeyStore);
  final payloadSigningConfig = await PayloadSigningKeyResolver(
    keyStore: payloadSigningKeyStore,
  ).resolve();
  getIt.registerSingleton<PayloadSigningConfig>(payloadSigningConfig);

  registerPlugDependencyGraph(getIt, odbcWorkerLocator: odbcWorkerLocator);
  getIt.registerLazySingleton<AppShutdownCoordinator>(
    () => AppShutdownCoordinator(
      hubConnectionShutdownRegistry: getIt<HubConnectionShutdownRegistry>(),
      transportClient: getIt.isRegistered<ITransportClient>() ? getIt<ITransportClient>() : null,
      autoUpdateOrchestrator: getIt.isRegistered<IAutoUpdateOrchestrator>() ? getIt<IAutoUpdateOrchestrator>() : null,
    ),
  );
  registerPlugCapabilityServices(getIt, capabilities);

  final transportSchemaLoader = TransportSchemaLoader();
  await transportSchemaLoader.loadAll();
  getIt.registerSingleton<TransportSchemaLoader>(transportSchemaLoader);
  getIt.registerSingleton<JsonSchemaContractValidator>(
    JsonSchemaContractValidator(
      loader: transportSchemaLoader,
      metrics: getIt<MetricsCollector>(),
    ),
  );

  final odbcInitResult = await getIt<odbc.OdbcService>().initialize();
  odbcInitResult.fold(
    (_) {},
    (error) {
      throw StateError(
        'ODBC initialization failed during startup: $error',
      );
    },
  );
  await _enableOdbcMetadataCacheIfConfigured(getIt<odbc.OdbcService>());

  getIt<OdbcEventBridge>();

  try {
    final database = getIt<AppDatabase>();
    await database.customStatement('PRAGMA foreign_keys = ON');
  } on GlobalStorageAccessException catch (error, stackTrace) {
    developer.log(
      'Unable to initialize global database storage',
      name: 'bootstrap_service_locator',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _throwGlobalStorageBootstrapError(error);
  }
}
