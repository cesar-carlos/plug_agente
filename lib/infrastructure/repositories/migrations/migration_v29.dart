part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseToV29(
  AppDatabase db,
  Migrator m,
) async {
  // ODBC credentials are externalized to flutter_secure_storage.
  // Legacy password/connection-string secrets remain in config_table until
  // OdbcCredentialStore lazy-migrates them on read. Do not NULL-out drift
  // columns here; dropping password is deferred to schema v30.
}
