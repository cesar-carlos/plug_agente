part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseV21ToV27(
  AppDatabase db,
  Migrator m,
  int from,
) async {
  if (from < 21) {
    await db.addAgentActionExecutionRuntimeIdentityColumnsIfMissing(m);
  }
  if (from < 22) {
    await db.addAgentActionRemoteAuditClientColumnsIfMissing(m);
  }
  if (from < 23) {
    await db.addAgentActionRemoteAuditRuntimeIdentityColumnsIfMissing(m);
  }
  if (from < 24) {
    await db.addAgentActionRemoteAuditIdempotencyKeyColumnIfMissing(m);
  }
  if (from < 25) {
    await m.createTable(db.agentActionCapturedOutputChunkTable);
    await db.addAgentActionExecutionCapturedOutputChunkColumnsIfMissing(m);
  }
  if (from < 26) {
    await db.addAgentActionDefinitionLastPreflightSnapshotHashColumnIfMissing(
      m,
    );
  }
  if (from < 27) {
    await db.addAgentActionDefinitionLastPreflightValidatedAtColumnIfMissing(
      m,
    );
  }
}
