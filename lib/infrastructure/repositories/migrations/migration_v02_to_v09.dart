part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseV02ToV09(
  AppDatabase db,
  Migrator m,
  int from,
) async {
  if (from < 2) {
    await m.addColumn(db.configTable, db.configTable.serverUrl);
    await m.addColumn(db.configTable, db.configTable.agentId);
  }
  if (from < 3) {
    await m.addColumn(
      db.configTable,
      db.configTable.authToken as GeneratedColumn<Object>,
    );
    await m.addColumn(
      db.configTable,
      db.configTable.refreshToken as GeneratedColumn<Object>,
    );
  }
  if (from < 4) {
    await m.addColumn(
      db.configTable,
      db.configTable.authUsername as GeneratedColumn<Object>,
    );
    await m.addColumn(
      db.configTable,
      db.configTable.authPassword as GeneratedColumn<Object>,
    );
  }
  if (from < 5) {
    await m.alterTable(
      // ignore: experimental_member_use - TableMigration is Drift's API for column defaults
      TableMigration(
        db.configTable,
        columnTransformer: {db.configTable.odbcDriverName: const Constant('')},
        newColumns: [db.configTable.odbcDriverName],
      ),
    );
  }
  if (from < 6) {
    await m.createTable(db.clientTokenCacheTable);
  }
  if (from < 7) {
    await m.addColumn(
      db.clientTokenCacheTable,
      db.clientTokenCacheTable.tokenHash,
    );
  }
  if (from < 8) {
    await m.addColumn(
      db.clientTokenCacheTable,
      db.clientTokenCacheTable.tokenValue,
    );
  }
  if (from < 9) {
    await m.addColumn(
      db.clientTokenCacheTable,
      db.clientTokenCacheTable.version,
    );
    await m.addColumn(
      db.clientTokenCacheTable,
      db.clientTokenCacheTable.updatedAt,
    );
    await db.customStatement(
      '''
      UPDATE client_token_cache_table
      SET updated_at = COALESCE(updated_at, synced_at, created_at)
      WHERE updated_at IS NULL
      ''',
    );
  }
}
