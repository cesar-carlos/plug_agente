import 'package:drift/drift.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class AgentActionRemoteAuditDriftStore implements IAgentActionRemoteAuditStore {
  AgentActionRemoteAuditDriftStore(this._database);

  final AppDatabase _database;

  @override
  Future<void> append(AgentActionRemoteAuditRecord record) async {
    await _database
        .into(_database.agentActionRemoteAuditTable)
        .insert(
          AgentActionRemoteAuditData(
            id: record.id,
            occurredAt: record.occurredAtUtc,
            rpcMethod: record.rpcMethod,
            actionId: record.actionId,
            executionId: record.executionId,
            traceId: record.traceId,
            requestedBy: record.requestedBy,
            outcome: record.outcome,
            reasonCode: record.reasonCode,
            rpcErrorCode: record.rpcErrorCode,
            credentialPresent: record.credentialPresent,
            clientId: record.clientId,
            tokenJti: record.tokenJti,
            runtimeInstanceId: record.runtimeInstanceId,
            runtimeSessionId: record.runtimeSessionId,
            idempotencyKey: record.idempotencyKey,
          ),
          mode: InsertMode.insert,
        );
  }

  @override
  Future<List<AgentActionRemoteAuditRecord>> listRecent({
    int limit = AgentActionRemoteAuditConstants.listRecentDefaultLimit,
  }) async {
    final clamped = AgentActionRemoteAuditConstants.clampListRecentLimit(limit);
    final rows =
        await (_database.select(_database.agentActionRemoteAuditTable)
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
              ..limit(clamped))
            .get();
    return rows.map(_rowToRecord).toList(growable: false);
  }

  AgentActionRemoteAuditRecord _rowToRecord(AgentActionRemoteAuditData row) {
    return AgentActionRemoteAuditRecord(
      id: row.id,
      occurredAtUtc: row.occurredAt,
      rpcMethod: row.rpcMethod,
      outcome: row.outcome,
      credentialPresent: row.credentialPresent,
      actionId: row.actionId,
      executionId: row.executionId,
      traceId: row.traceId,
      requestedBy: row.requestedBy,
      reasonCode: row.reasonCode,
      rpcErrorCode: row.rpcErrorCode,
      clientId: row.clientId,
      tokenJti: row.tokenJti,
      runtimeInstanceId: row.runtimeInstanceId,
      runtimeSessionId: row.runtimeSessionId,
      idempotencyKey: row.idempotencyKey,
    );
  }

  @override
  Future<int> deleteWhereOccurredBefore({
    required DateTime cutoffUtc,
    required int limit,
  }) async {
    if (limit <= 0) {
      return 0;
    }
    // Single-statement DELETE with subquery: replaces the previous
    // SELECT-then-DELETE pair which materialised entire rows just to read
    // their IDs and then sent them back as IN-list parameters. The subquery
    // uses the `idx_agent_action_remote_audit_occurred` index for the range
    // scan and SQLite executes the DELETE atomically on its own — no
    // explicit transaction needed.
    return _database.customUpdate(
      'DELETE FROM agent_action_remote_audit_table '
      'WHERE id IN ( '
      'SELECT id FROM agent_action_remote_audit_table '
      'WHERE occurred_at < ? '
      'ORDER BY occurred_at ASC '
      'LIMIT ? '
      ')',
      variables: [
        Variable.withDateTime(cutoffUtc),
        Variable<int>(limit),
      ],
      updates: {_database.agentActionRemoteAuditTable},
      updateKind: UpdateKind.delete,
    );
  }
}
