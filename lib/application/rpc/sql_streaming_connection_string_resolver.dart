import 'package:plug_agente/core/utils/odbc_connection_string_database_override.dart';
import 'package:plug_agente/domain/entities/config.dart';

/// Resolves the ODBC connection string used by DB streaming execution.
///
/// Mirrors the ODBC connection-string rewrite used by sql.execute streaming.
String resolveSqlStreamingConnectionString(
  Config config, {
  String? databaseOverride,
}) {
  final override = databaseOverride?.trim();
  final resolved = config.resolveConnectionString().trim();

  if (override != null && override.isNotEmpty) {
    if (resolved.isNotEmpty) {
      return OdbcConnectionStringDatabaseOverride.override(resolved, override);
    }
    return config.copyWith(databaseName: override).resolveConnectionString();
  }

  return resolved;
}
