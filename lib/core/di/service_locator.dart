import 'dart:developer' as developer;
import 'dart:io' as io;

import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_sequence.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/use_cases/apply_agent_action_on_app_exit_policies.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/feature_flags_env_seeder.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/plug_dependency_registrar.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_key_resolver.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_payload_signing_key_store.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt getIt = GetIt.instance;

odbc.ServiceLocator _odbcLocator = odbc.ServiceLocator();
bool _appCloseActionsDispatched = false;

/// Resets module-level shutdown flags between tests.
///
/// Production shutdown does not call [GetIt.reset]; tests that exercise
/// [shutdownApp] should invoke this helper in tearDown when they need a
/// clean dispatch gate without tearing down the DI graph.
void resetShutdownStateForTesting() {
  _appCloseActionsDispatched = false;
}

/// Shutdown centralizado de todos os recursos.
///
/// Sequência de encerramento:
/// 0. Aplicar silent update pendente (antes de parar o orchestrator)
/// 1. Parar auto-update e desconectar hub via [AppShutdownCoordinator]
/// 2. Parar purges periodicos
/// 3. Marcar subsistema de acoes como draining e despachar gatilhos app-close
/// 3b. Aplicar onAppExitPolicy
/// 4. Dispor fila SQL
/// 5. Fechar pool de conexoes ODBC
/// 6. Fechar banco local (Drift)
/// 7. Encerrar metricas e tray
/// 8. Encerrar worker ODBC
Future<void> shutdownApp() async {
  await _launchPendingSilentUpdateHelperIfReady();
  await _runEarlyShutdownCoordinator();

  await AppShutdownSequence(getIt).run(
    runEarlyShutdownCoordinator: _runEarlyShutdownCoordinator,
    dispatchAppCloseAgentActions: _dispatchAppCloseAgentActions,
    applyOnAppExitPolicies: _applyAgentActionOnAppExitPolicies,
    shutdownOdbcWorker: () => _odbcLocator.shutdown(),
    resetShutdownStateForTesting: resetShutdownStateForTesting,
  );
}

Future<void> _runEarlyShutdownCoordinator() async {
  if (getIt.isRegistered<AppShutdownCoordinator>()) {
    await getIt<AppShutdownCoordinator>().runEarlyShutdownPhase();
    return;
  }

  final shutdownCoordinator = AppShutdownCoordinator(
    hubConnectionShutdownRegistry: getIt.isRegistered<HubConnectionShutdownRegistry>()
        ? getIt<HubConnectionShutdownRegistry>()
        : HubConnectionShutdownRegistry(),
    transportClient: getIt.isRegistered<ITransportClient>() ? getIt<ITransportClient>() : null,
    autoUpdateOrchestrator: getIt.isRegistered<IAutoUpdateOrchestrator>() ? getIt<IAutoUpdateOrchestrator>() : null,
  );
  await shutdownCoordinator.runEarlyShutdownPhase();
}

/// Fires the silent update helper when an installer was previously staged
/// on disk. Guarded by `hasPendingDownloadedUpdate` so this is a no-op for
/// every shutdown that is not consuming a prepared update. Errors are
/// logged and swallowed: the shutdown sequence must continue even if the
/// helper failed to start (the next boot will re-evaluate the pending
/// record via `reconcilePendingAndSchedule`).
Future<void> _launchPendingSilentUpdateHelperIfReady() async {
  if (!getIt.isRegistered<IAutoUpdateOrchestrator>()) {
    return;
  }
  final orchestrator = getIt<IAutoUpdateOrchestrator>();
  if (!await orchestrator.hasPendingDownloadedUpdate) {
    return;
  }
  try {
    // `triggerAppClose: false` because we are already inside the shutdown
    // sequence — re-entering the close callback would recurse and call
    // shutdownApp() a second time.
    final result = await orchestrator.applyPendingSilentUpdate(
      triggerAppClose: false,
    );
    result.fold(
      (_) => developer.log(
        'Pending silent update helper launched from shutdown path',
        name: 'service_locator',
        level: 800,
      ),
      (failure) => developer.log(
        'Failed to launch pending silent update helper during shutdown',
        name: 'service_locator',
        level: 900,
        error: failure,
      ),
    );
  } on Object catch (error, stackTrace) {
    developer.log(
      'Pending silent update helper launch threw during shutdown',
      name: 'service_locator',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _applyAgentActionOnAppExitPolicies() async {
  if (!getIt.isRegistered<ApplyAgentActionOnAppExitPolicies>()) {
    return;
  }

  try {
    final result = await getIt<ApplyAgentActionOnAppExitPolicies>()();
    result.fold(
      (counts) {
        if (counts.queuedCancelled > 0 || counts.runningHandled > 0) {
          developer.log(
            'Applied onAppExit policies '
            '(queued_cancelled=${counts.queuedCancelled}, running_handled=${counts.runningHandled})',
            name: 'service_locator',
            level: 800,
          );
        }
      },
      (failure) {
        developer.log(
          'Failed to apply agent action onAppExit policies',
          name: 'service_locator',
          level: 900,
          error: failure,
        );
      },
    );
  } on Object catch (error, stackTrace) {
    developer.log(
      'Failed to apply agent action onAppExit policies',
      name: 'service_locator',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _dispatchAppCloseAgentActions() async {
  if (_appCloseActionsDispatched) {
    return;
  }
  _appCloseActionsDispatched = true;

  if (!getIt.isRegistered<AgentActionTriggerScheduler>()) {
    return;
  }

  try {
    final scheduler = getIt<AgentActionTriggerScheduler>();
    final result = await scheduler.dispatchAppCloseTriggers();
    result.fold(
      (count) {
        if (count > 0) {
          developer.log(
            'Dispatched $count app-close agent action trigger(s)',
            name: 'service_locator',
            level: 800,
          );
        }
      },
      (failure) {
        developer.log(
          'Failed to dispatch app-close agent action triggers',
          name: 'service_locator',
          level: 900,
          error: failure,
        );
      },
    );
    scheduler.stop();
  } on Object catch (error, stackTrace) {
    developer.log(
      'Failed to dispatch app-close agent action triggers',
      name: 'service_locator',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<bool> reloadOdbcRuntimeDependencies() async {
  try {
    if (getIt.isRegistered<ITransportClient>()) {
      await getIt<ITransportClient>().disconnect();
    }

    if (getIt.isRegistered<ISqlInvestigationCollector>()) {
      getIt<ISqlInvestigationCollector>().clear();
    }

    if (getIt.isRegistered<IConnectionPool>()) {
      await getIt<IConnectionPool>().closeAll();
    }

    if (getIt.isRegistered<OdbcEventBridge>()) {
      await getIt<OdbcEventBridge>().dispose();
    }

    await _resetLazySingletonIfRegistered<ITransportClient>();
    await _resetLazySingletonIfRegistered<RpcMethodDispatcher>();
    await _resetLazySingletonIfRegistered<OdbcNativeMetricsService>();
    await _resetLazySingletonIfRegistered<OdbcEventBridge>();
    await _resetLazySingletonIfRegistered<IStreamingDatabaseGateway>();
    await _resetLazySingletonIfRegistered<IDatabaseGateway>();
    await _resetLazySingletonIfRegistered<SqlExecutionQueue>();
    await _resetLazySingletonIfRegistered<DirectOdbcConnectionLimiter>();
    await _resetLazySingletonIfRegistered<IConnectionPool>();

    // Reload persisted ODBC settings so the new pool size / tuning take effect
    // before priming the singletons that depend on them.
    final odbcSettings = getIt<IOdbcConnectionSettings>();
    await odbcSettings.load();

    // Recalculate and replace the OdbcRuntimeTuning singleton so components
    // reading asyncWorkerCount / asyncMaxPendingRequests see the updated values.
    final newTuning = resolveOdbcRuntimeTuning(settings: odbcSettings);
    if (getIt.isRegistered<OdbcRuntimeTuning>()) {
      getIt.unregister<OdbcRuntimeTuning>();
    }
    getIt.registerSingleton<OdbcRuntimeTuning>(newTuning);
    _logOdbcRuntimeTuningWarnings(newTuning);

    // Re-initialize the ODBC worker pool with the updated tuning.
    // failFast is intentional here: SqlExecutionQueue at the application
    // layer already owns backpressure / queueing. We want the ODBC async
    // pool to reject overflow immediately so the queue (which has fairness,
    // timeouts and observability) is the single point of admission control.
    _odbcLocator.shutdown();
    _odbcLocator.initialize(
      useAsync: true,
      asyncWorkerCount: newTuning.asyncWorkerCount,
      asyncMaxPendingRequests: newTuning.asyncMaxPendingRequests,
      asyncBackpressureMode: odbc.AsyncBackpressureMode.failFast,
    );

    await _primeReloadedOdbcRuntimeDependencies();
    return true;
  } on Object catch (error, stackTrace) {
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

Future<void> _primeReloadedOdbcRuntimeDependencies() async {
  final odbcInitResult = await getIt<odbc.OdbcService>().initialize();
  odbcInitResult.fold(
    (_) {},
    (error) {
      throw StateError('ODBC initialization failed after reload: $error');
    },
  );

  // Recreate the main ODBC-facing singletons immediately so settings screens
  // fail fast instead of deferring DI/configuration problems to the next query.
  getIt<DirectOdbcConnectionLimiter>();
  getIt<IConnectionPool>();
  getIt<IStreamingDatabaseGateway>();
  getIt<IDatabaseGateway>();
  getIt<OdbcEventBridge>();
}

PayloadSigningKeyStore _createPayloadSigningKeyStore() {
  try {
    return FlutterSecurePayloadSigningKeyStore();
  } on Object catch (error, stackTrace) {
    developer.log(
      'FlutterSecurePayloadSigningKeyStore init failed, payload signing keys will use environment only',
      name: 'service_locator',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    return const NoopPayloadSigningKeyStore();
  }
}

Future<void> _resetLazySingletonIfRegistered<T extends Object>() async {
  if (!getIt.isRegistered<T>()) {
    return;
  }
  await getIt.resetLazySingleton<T>();
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
        name: 'service_locator',
        level: 800,
      );
    }
  } on Exception catch (e, stackTrace) {
    developer.log(
      'Failed to migrate legacy user preferences (continuing)',
      name: 'service_locator',
      level: 900,
      error: e,
      stackTrace: stackTrace,
    );
  }
}

OdbcRuntimeTuning resolveOdbcRuntimeTuning({
  required IOdbcConnectionSettings settings,
  int? processorCount,
}) {
  return OdbcRuntimeTuning.forPoolSize(
    poolSize: settings.poolSize,
    processorCount: processorCount ?? io.Platform.numberOfProcessors,
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

  // Warn only when pending slots are fewer than the concurrent dispatch count.
  // Comparing against sqlQueueMaxSize (queue depth) is misleading: the queue
  // dispatches at most sqlQueueMaxWorkers requests concurrently, not the full
  // queue depth, so the relevant bound is the worker count, not the queue size.
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
    return await GlobalStoragePathResolver.resolveContext();
  } on GlobalStorageAccessException catch (error, stackTrace) {
    developer.log(
      'Unable to resolve global storage context',
      name: 'service_locator',
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
    name: 'service_locator',
    level: 800,
  );

  if (!capabilities.canRunCore) {
    throw StateError(
      'Cannot run application: ${capabilities.degradationReasons.join(", ")}',
    );
  }

  ensureIanaTimeZoneDataLoaded();

  // Register capabilities globally
  getIt.registerSingleton<RuntimeCapabilities>(capabilities);
  getIt.registerSingleton<HubConnectionShutdownRegistry>(HubConnectionShutdownRegistry());
  if (runtimeDetectionDiagnostics != null) {
    getIt.registerSingleton<RuntimeDetectionDiagnostics>(
      runtimeDetectionDiagnostics,
    );
  }

  final globalStorageContext = await _resolveGlobalStorageContextOrThrow();
  getIt.registerSingleton<GlobalStorageContext>(globalStorageContext);

  final appSettings = GlobalAppSettingsStore(
    filePath: globalStorageContext.settingsFilePath,
  );
  try {
    await appSettings.initialize();
  } on GlobalStorageAccessException catch (error, stackTrace) {
    developer.log(
      'Unable to initialize global settings storage',
      name: 'service_locator',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _throwGlobalStorageBootstrapError(error);
  }
  await _migrateLegacyUserPreferences(appSettings);
  await FeatureFlagsEnvSeeder.applyUnsetOverrides(appSettings);
  getIt.registerSingleton<IAppSettingsStore>(appSettings);

  final agentRuntimeIdentity = await AgentRuntimeIdentity.load(settings: appSettings);
  getIt.registerSingleton<AgentRuntimeIdentity>(agentRuntimeIdentity);

  final odbcSettings = OdbcConnectionSettings(appSettings);
  await odbcSettings.load();
  getIt.registerSingleton<IOdbcConnectionSettings>(odbcSettings);

  final odbcRuntimeTuning = resolveOdbcRuntimeTuning(settings: odbcSettings);
  getIt.registerSingleton<OdbcRuntimeTuning>(odbcRuntimeTuning);
  _logOdbcRuntimeTuningWarnings(odbcRuntimeTuning);
  // failFast is intentional: SqlExecutionQueue at the application layer
  // owns admission control / queueing / fairness. The ODBC async pool
  // rejects overflow immediately so the queue stays the single source of
  // truth for backpressure decisions.
  _odbcLocator.initialize(
    useAsync: true,
    asyncWorkerCount: odbcRuntimeTuning.asyncWorkerCount,
    asyncMaxPendingRequests: odbcRuntimeTuning.asyncMaxPendingRequests,
    asyncBackpressureMode: odbc.AsyncBackpressureMode.failFast,
  );
  developer.log(
    'ODBC async worker pool configured '
    '(poolSize: ${odbcRuntimeTuning.poolSize}, '
    'workerCount: ${odbcRuntimeTuning.asyncWorkerCount}, '
    'maxPendingRequests: ${odbcRuntimeTuning.asyncMaxPendingRequests}, '
    'backpressureMode: ${odbcRuntimeTuning.asyncBackpressureMode})',
    name: 'service_locator',
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

  registerPlugDependencyGraph(getIt, odbcWorkerLocator: _odbcLocator);
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

  // Force creation of the ODBC event bridge so it starts consuming the
  // runtime event stream from boot, not lazily on first diagnostic access.
  getIt<OdbcEventBridge>();

  // Initialize database
  try {
    final database = getIt<AppDatabase>();
    await database.customStatement('PRAGMA foreign_keys = ON');
  } on GlobalStorageAccessException catch (error, stackTrace) {
    developer.log(
      'Unable to initialize global database storage',
      name: 'service_locator',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    _throwGlobalStorageBootstrapError(error);
  }
}
