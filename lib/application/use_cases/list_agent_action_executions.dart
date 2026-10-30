import 'package:plug_agente/application/actions/action_io_execution_projection.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_execution_ownership.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_history.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_history_page.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class ListAgentActionExecutions {
  const ListAgentActionExecutions(this._repository, {IActionIoLocalHistory? ioHistory}) : _ioHistory = ioHistory;

  final IAgentActionRepository _repository;
  final IActionIoLocalHistory? _ioHistory;

  Future<Result<List<AgentActionExecution>>> call({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    String? resolvedActionId;
    if (actionId != null) {
      final trimmed = actionId.trim();
      if (trimmed.isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Action id filter cannot be blank when listing executions.',
            context: const {
              'field': 'actionId',
              'reason': AgentActionValidationConstants.blankFilterReason,
              'user_message': 'Remova o filtro de acao ou informe um identificador valido.',
            },
          ),
        );
      }
      resolvedActionId = trimmed;
    }

    String? resolvedIdempotencyKey;
    if (idempotencyKey != null) {
      final trimmed = idempotencyKey.trim();
      if (trimmed.isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Idempotency key filter cannot be blank when listing executions.',
            context: const {
              'field': 'idempotencyKey',
              'reason': AgentActionValidationConstants.blankFilterReason,
              'user_message': 'Remova o filtro de idempotencia ou informe um valor valido.',
            },
          ),
        );
      }
      resolvedIdempotencyKey = trimmed;
    }

    final history = _ioHistory;
    final repository = _repository;
    final effectiveLimit = AgentActionRuntimeStateConstants.resolveListExecutionsLimit(limit);
    final Result<List<AgentActionExecution>> legacy;
    if (repository is IAgentActionHistoryPage && history is IActionIoExecutionOwnership) {
      final retained = <AgentActionExecution>[];
      AgentActionHistoryCursor? cursor;
      while (effectiveLimit == null || retained.length < effectiveLimit) {
        final page = await (repository as IAgentActionHistoryPage).listExecutionPage(
          limit: 200,
          after: cursor,
          actionId: resolvedActionId,
          idempotencyKey: resolvedIdempotencyKey,
          statuses: statuses,
          requestedAfter: requestedAfter,
        );
        if (page.isError()) return Failure(page.exceptionOrNull()!);
        final rows = page.getOrThrow();
        if (rows.isEmpty) break;
        for (final entry in rows) {
          final owned = await (history! as IActionIoExecutionOwnership).ownsExecution(entry.id);
          if (owned.isError()) return Failure(owned.exceptionOrNull()!);
          if (!owned.getOrThrow()) retained.add(entry);
          if (effectiveLimit != null && retained.length >= effectiveLimit) break;
        }
        final last = rows.last;
        cursor = AgentActionHistoryCursor(last.requestedAt, last.id);
        if (rows.length < 200) break;
      }
      legacy = Success(retained);
    } else {
      legacy = await _repository.listExecutions(
        actionId: resolvedActionId,
        idempotencyKey: resolvedIdempotencyKey,
        statuses: statuses,
        requestedAfter: requestedAfter,
        // Journal reconciliation can remove stale legacy matches; apply the cap
        // only after authoritative states have replaced those projections.
        limit: _ioHistory == null ? limit : 0,
      );
    }
    if (legacy.isError() || history == null) return legacy;
    final entries = {for (final entry in legacy.getOrThrow()) entry.id: entry};
    final journalEntries = <AgentActionExecution>[];
    ActionIoHistoryCursor? cursor;
    for (;;) {
      final page = await history.listExecutionSnapshots(
        limit: IActionIoLocalHistory.maxPageSize,
        after: cursor,
        actionId: resolvedActionId,
        idempotencyKey: resolvedIdempotencyKey,
        requestedAfter: requestedAfter,
      );
      if (page.isError()) return Failure(page.exceptionOrNull()!);
      final snapshots = page.getOrThrow();
      if (snapshots.isEmpty) break;
      for (final snapshot in snapshots) {
        final projected = ActionIoExecutionProjection.fromSnapshot(snapshot);
        if (projected.isError()) return Failure(projected.exceptionOrNull()!);
        final entry = projected.getOrThrow();
        entries.remove(entry.id);
        // Pages are ordered newest first. Continue reconciliation of legacy IDs,
        // but retain only the journal candidates that can reach the result.
        if ((statuses == null || statuses.isEmpty || statuses.contains(entry.status)) &&
            (effectiveLimit == null || journalEntries.length < effectiveLimit)) {
          journalEntries.add(entry);
        }
      }
      final last = snapshots.last;
      cursor = ActionIoHistoryCursor(last.createdAt, last.session.executionId);
      if (snapshots.length < IActionIoLocalHistory.maxPageSize) break;
    }
    final ordered = [...entries.values, ...journalEntries]
      ..sort((a, b) {
        final date = b.requestedAt.compareTo(a.requestedAt);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    return Success(effectiveLimit == null ? ordered : ordered.take(effectiveLimit).toList(growable: false));
  }
}
