import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class ListRecentAgentActionRemoteAudit {
  const ListRecentAgentActionRemoteAudit(this._store);

  final IAgentActionRemoteAuditStore _store;

  Future<Result<List<AgentActionRemoteAuditRecord>>> call({
    int limit = AgentActionRemoteAuditConstants.listRecentDefaultLimit,
  }) async {
    try {
      final rows = await _store.listRecent(limit: limit);
      return Success(rows);
    } on Object catch (error, stackTrace) {
      return Failure(
        ServerFailure.withContext(
          message: 'Failed to list agent action remote audit rows',
          cause: error,
          context: {
            'operation': 'list_recent_agent_action_remote_audit',
            'stack_trace': stackTrace.toString(),
          },
        ),
      );
    }
  }
}
