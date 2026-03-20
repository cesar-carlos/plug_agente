import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';

/// Builds the ODBC pool implementation for the current persisted settings.
///
/// Default is lease-based [OdbcConnectionPool] (correct `ConnectionOptions` per
/// connection). Enable [IOdbcConnectionSettings.useNativeOdbcPool] only when
/// testing performance or after upstream fixes to native pool buffers.
IConnectionPool createOdbcConnectionPool(
  OdbcService service,
  IOdbcConnectionSettings settings,
) {
  if (settings.useNativeOdbcPool) {
    return OdbcNativeConnectionPool(service, settings);
  }
  return OdbcConnectionPool(service, settings);
}
