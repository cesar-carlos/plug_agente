import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/infrastructure/config/database_type.dart';

/// Maps persisted ODBC driver names to the local SQL dialect used by builders.
DatabaseType mapOdbcDriverNameToDatabaseType(String driverName) {
  final exact = switch (driverName) {
    'SQL Server' => DatabaseType.sqlServer,
    'PostgreSQL' => DatabaseType.postgresql,
    'SQL Anywhere' => DatabaseType.sybaseAnywhere,
    _ => null,
  };
  if (exact != null) {
    return exact;
  }

  final detected = odbc.DatabaseType.fromDriverName(driverName);
  final mapped = switch (detected) {
    odbc.DatabaseType.sqlServer => DatabaseType.sqlServer,
    odbc.DatabaseType.postgresql => DatabaseType.postgresql,
    odbc.DatabaseType.sybaseAsa => DatabaseType.sybaseAnywhere,
    _ => null,
  };
  if (mapped != null) {
    return mapped;
  }

  developer.log(
    'Unsupported ODBC driver detected; falling back to sqlServer dialect. '
    'SQL generation may produce incorrect statements for this engine.',
    name: 'database_gateway',
    level: 1000,
    error: <String, Object?>{
      'driver_name': driverName,
      'detected_engine': detected.name,
      'supported_dialects': <String>['sqlServer', 'postgresql', 'sybaseAnywhere'],
    },
  );
  return DatabaseType.sqlServer;
}
