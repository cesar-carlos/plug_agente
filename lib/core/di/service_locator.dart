import 'dart:developer' as developer;

import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/di/plug_dependency_registrar.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt getIt = GetIt.instance;

odbc.ServiceLocator _odbcLocator = odbc.ServiceLocator();

/// Shutdown centralizado de todos os recursos.
///
/// Sequência de encerramento:
/// 1. Desconectar transporte (WebSocket)
/// 2. Dispor fila SQL
/// 3. Fechar pool de conexões ODBC
/// 4. Fechar banco local (Drift)
/// 5. Encerrar worker ODBC
Future<void> shutdownApp() async {
  // 1. Desconectar transporte
  if (getIt.isRegistered<ITransportClient>()) {
    final transport = getIt<ITransportClient>();
    await transport.disconnect();
  }

  // 2. Dispor fila SQL (antes de fechar o pool)
  if (getIt.isRegistered<IDatabaseGateway>()) {
    final gateway = getIt<IDatabaseGateway>();
    if (gateway is QueuedDatabaseGateway) {
      gateway.dispose();
      developer.log(
        'SQL execution queue disposed',
        name: 'service_locator',
        level: 800,
      );
    }
  }

  // 3. Fechar pool de conexões
  if (getIt.isRegistered<IConnectionPool>()) {
    final pool = getIt<IConnectionPool>();
    await pool.closeAll();
  }

  // 4. Fechar banco local
  if (getIt.isRegistered<AppDatabase>()) {
    final db = getIt<AppDatabase>();
    await db.close();
  }

  // 5. Dispose metrics collectors
  if (getIt.isRegistered<MetricsCollector>()) {
    getIt<MetricsCollector>().dispose();
  }
  if (getIt.isRegistered<ProtocolMetricsCollector>()) {
    getIt<ProtocolMetricsCollector>().dispose();
  }
  if (getIt.isRegistered<SqlInvestigationCollector>()) {
    getIt<SqlInvestigationCollector>().dispose();
  }

  // 6. Encerrar worker ODBC (synchronous)
  _odbcLocator.shutdown();
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

    await _resetLazySingletonIfRegistered<ITransportClient>();
    await _resetLazySingletonIfRegistered<RpcMethodDispatcher>();
    await _resetLazySingletonIfRegistered<OdbcNativeMetricsService>();
    await _resetLazySingletonIfRegistered<IStreamingDatabaseGateway>();
    await _resetLazySingletonIfRegistered<IDatabaseGateway>();
    await _resetLazySingletonIfRegistered<DirectOdbcConnectionLimiter>();
    await _resetLazySingletonIfRegistered<IConnectionPool>();
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

  // Register capabilities globally
  getIt.registerSingleton<RuntimeCapabilities>(capabilities);

  _odbcLocator.initialize(useAsync: true);
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
  getIt.registerSingleton<IAppSettingsStore>(appSettings);

  final odbcSettings = OdbcConnectionSettings(appSettings);
  await odbcSettings.load();
  getIt.registerSingleton<IOdbcConnectionSettings>(odbcSettings);

  final featureFlags = FeatureFlags(appSettings);
  getIt.registerSingleton<FeatureFlags>(featureFlags);

  final hubResilienceConfig = HubResilienceConfig(featureFlags);
  getIt.registerSingleton<HubResilienceConfig>(hubResilienceConfig);

  registerPlugDependencyGraph(getIt, odbcWorkerLocator: _odbcLocator);
  registerPlugCapabilityServices(getIt, capabilities);

  final odbcInitResult = await getIt<odbc.OdbcService>().initialize();
  odbcInitResult.fold(
    (_) {},
    (error) {
      throw StateError(
        'ODBC initialization failed during startup: $error',
      );
    },
  );

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
