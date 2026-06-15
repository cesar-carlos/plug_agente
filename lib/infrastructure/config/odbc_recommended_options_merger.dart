import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';

/// Profile defaults from odbc ServiceLocator after initialize.
final class OdbcProfileRecommendedOptions {
  const OdbcProfileRecommendedOptions({
    required this.connection,
    required this.pool,
  });

  final odbc.ConnectionOptions connection;
  final odbc.PoolOptions pool;
}

/// Merges plug_agente acquire options with [odbc.ServiceLocator] profile defaults.
///
/// UI-driven buffer sizes, login/query timeouts, and reconnect policy from
/// [ConnectionAcquireOptions] win; profile fields such as slowQueryThreshold on
/// odbc.ConnectionOptions are applied when plug options do not set them.
final class OdbcRecommendedOptionsMerger {
  OdbcRecommendedOptionsMerger._();

  static bool lazyStringsForConnectionString(String connectionString) {
    return connectionStringBenefitsFromLazyStrings(connectionString);
  }

  static odbc.ConnectionOptions mergeConnectionOptions({
    required ConnectionAcquireOptions plugOptions,
    required odbc.ConnectionOptions recommended,
    bool lazyStrings = false,
  }) {
    return odbc.ConnectionOptions(
      connectionTimeout: recommended.connectionTimeout,
      loginTimeout: plugOptions.loginTimeout,
      queryTimeout: plugOptions.queryTimeout,
      maxResultBufferBytes: plugOptions.maxResultBufferBytes,
      initialResultBufferBytes: plugOptions.initialResultBufferBytes,
      autoReconnectOnConnectionLost:
          plugOptions.autoReconnectOnConnectionLost ?? recommended.autoReconnectOnConnectionLost,
      maxReconnectAttempts: plugOptions.maxReconnectAttempts ?? recommended.maxReconnectAttempts,
      reconnectBackoff: plugOptions.reconnectBackoff ?? recommended.reconnectBackoff,
      slowQueryThreshold: recommended.slowQueryThreshold,
      lazyStrings: lazyStrings,
    );
  }

  static odbc.PoolOptions mergePoolOptions({
    required odbc.PoolOptions recommended,
    odbc.PoolOptions? plugOverrides,
  }) {
    if (plugOverrides == null || !plugOverrides.hasAnyOption) {
      return recommended;
    }
    return odbc.PoolOptions(
      idleTimeout: plugOverrides.idleTimeout ?? recommended.idleTimeout,
      maxLifetime: plugOverrides.maxLifetime ?? recommended.maxLifetime,
      connectionTimeout: plugOverrides.connectionTimeout ?? recommended.connectionTimeout,
    );
  }
}
