part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseToV30(
  AppDatabase db,
  Migrator m,
) async {
  // Destructive migration: drops plaintext password column from config_table.
  // v29 kept the column so OdbcCredentialStore could lazy-migrate stragglers
  // into flutter_secure_storage on read. Before dropping, copy any remaining
  // drift passwords into secure storage (when available) and redact embedded
  // PWD segments from connection_string so secrets are not left in drift.
  final columns = await db.readConfigTableColumnNames();
  if (!columns.contains('password')) {
    return;
  }

  await db.migrateRemainingOdbcPasswordsBeforeColumnDrop();

  // ignore: experimental_member_use
  await m.alterTable(TableMigration(db.configTable));
}
