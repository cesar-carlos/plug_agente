part of '../agent_config_drift_database.dart';

Future<void> migrateAgentConfigDatabaseToV28(
  AppDatabase db,
  Migrator m,
) async {
  // Recreate AgentActionTriggerTable and AgentActionCapturedOutputChunkTable
  // to add REFERENCES (FK) constraints. TableMigration copies data and
  // recreates the table with the updated schema.
  // AgentActionExecutionTable.actionId is intentionally left without a FK
  // to preserve execution history after definition deletion (enforced at
  // the repository level in deleteDefinition).
  //
  // Pre-clean orphan rows before introducing FKs: rows whose parent has
  // already been deleted would fail the FK check during table copy and
  // could fail the migration entirely. The repository-level cascade was
  // best-effort; pre-existing orphans (e.g. from before this rule) are
  // resolved by deleting them here so the migration is idempotent.
  await db.customStatement(
    '''
    DELETE FROM agent_action_trigger_table
    WHERE action_id NOT IN (SELECT id FROM agent_action_definition_table)
    ''',
  );
  await db.customStatement(
    '''
    DELETE FROM agent_action_captured_output_chunk_table
    WHERE execution_id NOT IN (SELECT id FROM agent_action_execution_table)
    ''',
  );
  // ignore: experimental_member_use - TableMigration is Drift's API for table recreation
  await m.alterTable(TableMigration(db.agentActionTriggerTable));
  // ignore: experimental_member_use
  await m.alterTable(TableMigration(db.agentActionCapturedOutputChunkTable));
}
