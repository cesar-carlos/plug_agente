part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseV14ToV20(
  AppDatabase db,
  Migrator m,
  int from,
) async {
  // Agent action tables are additive-only: never drop or recreate them on upgrade.
  // Failed migrations follow the global Drift policy (app startup fails safely).
  if (from < 14) {
    await m.createTable(db.agentActionDefinitionTable);
    await m.createTable(db.agentActionExecutionTable);
  }
  if (from < 15) {
    await m.createTable(db.agentActionTriggerTable);
  }
  if (from < 16) {
    await db.addAgentActionExecutionTriggerColumnsIfMissing(m);
  }
  if (from < 17) {
    await db.addAgentActionExecutionProcessIdentityColumnsIfMissing(m);
  }
  if (from < 18) {
    await db.addAgentActionExecutionFailurePhaseColumnIfMissing(m);
  }
  if (from < 19) {
    await m.createTable(db.rpcIdempotencyCacheTable);
  }
  if (from < 20) {
    await m.createTable(db.agentActionRemoteAuditTable);
  }
}
