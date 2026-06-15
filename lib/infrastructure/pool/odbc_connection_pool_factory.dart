import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';

/// Builds the ODBC pool implementation for the current persisted settings.
///
/// Default behaviour (feature flag default = `true`):
/// - SQL Server and PostgreSQL → [AdaptiveOdbcConnectionPool] routes them to the
///   native pool ([OdbcNativeConnectionPool] via `poolGetConnection`), which
///   reuses open connections and avoids an ODBC handshake on every query.
/// - SQL Anywhere → [AdaptiveOdbcConnectionPool] falls back to the lease pool
///   because some SQL Anywhere ODBC drivers return invalid handles under the
///   native pool and cause worker timeouts under concurrent load.
/// - Queries that supply [ConnectionAcquireOptions] (e.g. buffer hints) always
///   route to the lease pool regardless of driver; the native pool does not
///   accept per-connection options.
///
/// When the feature flag is disabled, [OdbcConnectionPool] (lease-based) is
/// always used: every query calls `connect`/`disconnect`, paying the full
/// ODBC handshake cost but applying exact `ConnectionOptions` per request.
IConnectionPool createOdbcConnectionPool(
  OdbcService service,
  IOdbcConnectionSettings settings,
  MetricsCollector metricsCollector,
  FeatureFlags featureFlags,
  Object? configContext, {
  OdbcProfileRecommendedOptions? recommendedOptions,
}) {
  final queryConfigSource = configContext is IQueryConfigSource ? configContext : null;
  final configRepository = configContext is IAgentConfigRepository ? configContext : null;
  if (featureFlags.enableOdbcExperimentalDriverAdaptivePooling) {
    return AdaptiveOdbcConnectionPool(
      leasePool: OdbcConnectionPool(
        service,
        settings,
        metricsCollector: metricsCollector,
        recommendedOptions: recommendedOptions,
      ),
      nativePool: OdbcNativeConnectionPool(
        service,
        settings,
        metricsCollector: metricsCollector,
        recommendedOptions: recommendedOptions,
      ),
      featureFlags: featureFlags,
      metricsCollector: metricsCollector,
      queryConfigSource: queryConfigSource,
      configRepository: configRepository,
      nativeWarmUpEnabled: ConnectionConstants.nativeWarmUpEnabled,
    );
  }

  return OdbcConnectionPool(
    service,
    settings,
    metricsCollector: metricsCollector,
    recommendedOptions: recommendedOptions,
  );
}
