import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';

/// Builds the ODBC pool implementation for the current persisted settings.
///
/// Default is lease-based [OdbcConnectionPool] (correct `ConnectionOptions` per
/// connection). Native ODBC pooling is disabled here because persisted settings
/// can otherwise reactivate the native pool, which returns invalid handles with
/// some SQL Anywhere drivers and causes worker timeouts under concurrent load.
IConnectionPool createOdbcConnectionPool(
  OdbcService service,
  IOdbcConnectionSettings settings,
  MetricsCollector metricsCollector,
) {
  return OdbcConnectionPool(
    service,
    settings,
    metricsCollector: metricsCollector,
  );
}
