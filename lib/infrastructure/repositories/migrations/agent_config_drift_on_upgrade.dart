part of '../agent_config_drift_database.dart';

Future<void> runAgentConfigDatabaseUpgrade(
  AppDatabase db,
  Migrator m,
  int from,
  int to,
) async {
  await migrateAgentConfigDatabaseV02ToV09(db, m, from);
  await migrateAgentConfigDatabaseV10ToV13(db, m, from);
  await migrateAgentConfigDatabaseV14ToV20(db, m, from);
  await migrateAgentConfigDatabaseV21ToV27(db, m, from);
  if (from < 28) {
    await migrateAgentConfigDatabaseToV28(db, m);
  }
  if (from < 29) {
    await migrateAgentConfigDatabaseToV29(db, m);
  }
  if (from < 30) {
    await migrateAgentConfigDatabaseToV30(db, m);
  }
  await db.createClientTokenIndexes();
  await db.createAgentActionIndexes();
  await db.createRpcIdempotencyIndexes();
  await db.createAgentActionRemoteAuditIndexes();
  await db.createAgentActionCapturedOutputChunkIndexes();
}
