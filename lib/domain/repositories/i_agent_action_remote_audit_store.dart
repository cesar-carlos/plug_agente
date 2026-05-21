import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';

abstract class IAgentActionRemoteAuditStore {
  Future<void> append(AgentActionRemoteAuditRecord record);

  /// Recent rows ordered by [AgentActionRemoteAuditRecord.occurredAtUtc] descending.
  Future<List<AgentActionRemoteAuditRecord>> listRecent({int limit = 200});

  /// Deletes up to [limit] rows with `occurred_at` strictly before [cutoffUtc].
  /// Returns the number of rows removed (best-effort).
  Future<int> deleteWhereOccurredBefore({
    required DateTime cutoffUtc,
    required int limit,
  });
}
