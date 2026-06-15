import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart' as app_db;

const String odbcEnableNativeBcpEnvKey = 'ODBC_ENABLE_NATIVE_BCP';
const String odbcNativeBcpUnavailableReason = 'native_bcp_unavailable';
const String odbcNativeBcpFailedReason = 'native_bcp_failed';

bool isOdbcNativeBcpPilotEnabled({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcEnableNativeBcpEnvKey))
      ?.trim()
      .toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

/// SQL Server bulk insert may use native BCP when the pilot flag is on and the
/// engine reports capability. Requires `ODBC_ENABLE_UNSTABLE_NATIVE_BCP=1` in the
/// process environment (read by `odbc_fast` at call time).
bool shouldAttemptNativeBcpBulkInsert({
  required app_db.DatabaseType? databaseType,
  DriverCapabilities? capabilities,
  String? pilotFlagRaw,
}) {
  if (databaseType != app_db.DatabaseType.sqlServer) {
    return false;
  }
  if (!isOdbcNativeBcpPilotEnabled(rawValue: pilotFlagRaw)) {
    return false;
  }
  if (capabilities == null) {
    return true;
  }
  return isNativeBcpAvailable(capabilities);
}

bool isNativeBcpUnsupportedError(Object error) {
  final message = switch (error) {
    OdbcError(:final message) => message,
    _ => error.toString(),
  };
  final lower = message.toLowerCase();
  return lower.contains("enable 'sqlserver-bcp' feature") ||
      lower.contains('odbc_enable_unstable_native_bcp') ||
      lower.contains('native sql server bcp is disabled') ||
      lower.contains('native sql server bcp is currently supported only');
}
