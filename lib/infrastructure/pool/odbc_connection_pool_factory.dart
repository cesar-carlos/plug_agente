import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';

/// Builds the ODBC pool implementation for the current persisted settings.
///
/// Default is lease-based [OdbcConnectionPool] (correct `ConnectionOptions` per
/// connection). Native ODBC pooling is disabled here because persisted settings
/// can otherwise reactivate the native pool, which returns invalid handles with
/// some SQL Anywhere drivers and causes worker timeouts under concurrent load.
/// Legacy `useNativeOdbcPool` settings remain readable for compatibility, but
/// are intentionally ignored by this production factory.
IConnectionPool createOdbcConnectionPool(
  OdbcService service,
  IOdbcConnectionSettings settings,
  MetricsCollector metricsCollector,
  FeatureFlags featureFlags,
  Object? configContext,
) {
  final activeConfigResolver = configContext is ActiveConfigResolver
      ? configContext
      : null;
  final configRepository = configContext is IAgentConfigRepository
      ? configContext
      : null;
  if (featureFlags.enableOdbcExperimentalDriverAdaptivePooling) {
    return AdaptiveOdbcConnectionPool(
      leasePool: OdbcConnectionPool(
        service,
        settings,
        metricsCollector: metricsCollector,
      ),
      nativePool: OdbcNativeConnectionPool(
        service,
        settings,
        metricsCollector: metricsCollector,
      ),
      featureFlags: featureFlags,
      metricsCollector: metricsCollector,
      activeConfigResolver: activeConfigResolver,
      configRepository: configRepository,
    );
  }

  return OdbcConnectionPool(
    service,
    settings,
    metricsCollector: metricsCollector,
  );
}
