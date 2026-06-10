part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseV10ToV13(
  AppDatabase db,
  Migrator m,
  int from,
) async {
  if (from < 10) {
    await db.addAgentProfileColumnsIfMissing(m);
  }
  if (from < 11) {
    await m.addColumn(
      db.configTable,
      db.configTable.hubProfileVersion as GeneratedColumn<Object>,
    );
    await m.addColumn(
      db.configTable,
      db.configTable.hubProfileUpdatedAt as GeneratedColumn<Object>,
    );
  }
  if (from < 12) {
    await db.addClientTokenNameColumnIfMissing(m);
  }
  if (from < 13) {
    await db.addClientTokenGlobalPermissionsColumnIfMissing(m);
    await db.customStatement(
      '''
      UPDATE client_token_cache_table
      SET global_permissions_json = CASE
        WHEN all_permissions = 1 THEN '{"read":true,"update":true,"delete":true,"ddl":true}'
        WHEN all_tables = 1 OR all_views = 1 THEN '{"read":true,"update":true,"delete":true,"ddl":false}'
        ELSE '{"read":false,"update":false,"delete":false,"ddl":false}'
      END
      WHERE global_permissions_json IS NULL
         OR TRIM(global_permissions_json) = ''
         OR global_permissions_json = '{"read":false,"update":false,"delete":false,"ddl":false}'
      ''',
    );
    await db.customStatement(
      '''
      UPDATE client_token_cache_table
      SET all_tables = 1,
          all_views = 1,
          all_permissions = 1,
          global_permissions_json = '{"read":true,"update":true,"delete":true,"ddl":true}'
      WHERE all_permissions = 1
      ''',
    );
  }
}
