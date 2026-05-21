import 'package:drift/drift.dart';
import 'package:plug_agente/application/actions/agent_action_captured_output_chunker.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_captured_output_chunk_store.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_drift_mapper.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionRepository implements IAgentActionRepository {
  AgentActionRepository(
    this._database, {
    AgentActionDriftMapper mapper = const AgentActionDriftMapper(),
  }) : _mapper = mapper,
       _capturedOutputChunks = AgentActionCapturedOutputChunkStore(_database);

  final AppDatabase _database;
  final AgentActionDriftMapper _mapper;
  final AgentActionCapturedOutputChunkStore _capturedOutputChunks;

  @override
  Future<Result<AgentActionDefinition>> saveDefinition(
    AgentActionDefinition definition,
  ) async {
    try {
      final now = DateTime.now();
      final row = _mapper.definitionToData(definition, now: now);
      await _database.into(_database.agentActionDefinitionTable).insertOnConflictUpdate(row);
      return Success(_mapper.definitionFromData(row));
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to save action definition',
          cause: error,
          context: {
            'operation': 'saveActionDefinition',
            'action_id': definition.id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<AgentActionDefinition>> getDefinition(String id) async {
    try {
      final row = await (_database.select(
        _database.agentActionDefinitionTable,
      )..where((table) => table.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return Failure(
          ActionNotFoundFailure.withContext(
            message: 'Action definition was not found.',
            context: {
              'operation': 'getActionDefinition',
              'action_id': id,
              'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
              'user_message': 'Acao nao encontrada. Atualize a lista e tente novamente.',
            },
          ),
        );
      }

      return Success(_mapper.definitionFromData(row));
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to load action definition',
          cause: error,
          context: {
            'operation': 'getActionDefinition',
            'action_id': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<List<AgentActionDefinition>>> listDefinitions() async {
    try {
      final rows =
          await (_database.select(_database.agentActionDefinitionTable)..orderBy([
                (table) => OrderingTerm.asc(table.name),
                (table) => OrderingTerm.asc(table.id),
              ]))
              .get();
      return Success(
        rows.map(_mapper.definitionFromData).toList(growable: false),
      );
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to list action definitions',
          cause: error,
          context: const {'operation': 'listActionDefinitions'},
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteDefinition(String id) async {
    try {
      var definitionExisted = false;
      await _database.transaction(() async {
        final existing = await (_database.select(
          _database.agentActionDefinitionTable,
        )..where((table) => table.id.equals(id))).getSingleOrNull();
        if (existing == null) {
          return;
        }

        definitionExisted = true;
        await (_database.delete(
          _database.agentActionTriggerTable,
        )..where((table) => table.actionId.equals(id))).go();
        await (_database.delete(
          _database.agentActionDefinitionTable,
        )..where((table) => table.id.equals(id))).go();
      });

      if (!definitionExisted) {
        return Failure(
          ActionNotFoundFailure.withContext(
            message: 'Action definition was not found.',
            context: {
              'operation': 'deleteActionDefinition',
              'action_id': id,
              'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
              'user_message': 'Acao nao encontrada. Atualize a lista e tente novamente.',
            },
          ),
        );
      }

      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to delete action definition',
          cause: error,
          context: {
            'operation': 'deleteActionDefinition',
            'action_id': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<AgentActionTrigger>> saveTrigger(
    AgentActionTrigger trigger,
  ) async {
    try {
      final now = DateTime.now();
      final row = _mapper.triggerToData(trigger, now: now);
      await _database.into(_database.agentActionTriggerTable).insertOnConflictUpdate(row);
      return Success(_mapper.triggerFromData(row));
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to save action trigger',
          cause: error,
          context: {
            'operation': 'saveActionTrigger',
            'trigger_id': trigger.id,
            'action_id': trigger.actionId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<AgentActionTrigger>> getTrigger(String id) async {
    try {
      final row = await (_database.select(
        _database.agentActionTriggerTable,
      )..where((table) => table.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return Failure(
          ActionNotFoundFailure.withContext(
            message: 'Action trigger was not found.',
            context: {
              'operation': 'getActionTrigger',
              'trigger_id': id,
              'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
              'user_message': 'Gatilho nao encontrado. Atualize a lista e tente novamente.',
            },
          ),
        );
      }

      return Success(_mapper.triggerFromData(row));
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to load action trigger',
          cause: error,
          context: {
            'operation': 'getActionTrigger',
            'trigger_id': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async {
    try {
      final query = _database.select(_database.agentActionTriggerTable)
        ..orderBy([
          (table) => OrderingTerm.asc(table.actionId),
          (table) => OrderingTerm.asc(table.type),
          (table) => OrderingTerm.asc(table.id),
        ]);
      if (actionId != null) {
        query.where((table) => table.actionId.equals(actionId));
      }
      if (isEnabled != null) {
        query.where((table) => table.isEnabled.equals(isEnabled));
      }
      if (types != null && types.isNotEmpty) {
        query.where(
          (table) => table.type.isIn(
            types.map((type) => type.name).toList(growable: false),
          ),
        );
      }

      final rows = await query.get();
      return Success(
        rows.map(_mapper.triggerFromData).toList(growable: false),
      );
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to list action triggers',
          cause: error,
          context: {
            'operation': 'listActionTriggers',
            'action_id': ?actionId,
            'is_enabled': ?isEnabled,
            'types': ?(types != null && types.isNotEmpty
                ? types.map((AgentActionTriggerType type) => type.name).toList(growable: false)
                : null),
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteTrigger(String id) async {
    try {
      final deleted = await (_database.delete(
        _database.agentActionTriggerTable,
      )..where((table) => table.id.equals(id))).go();
      if (deleted == 0) {
        return Failure(
          ActionNotFoundFailure.withContext(
            message: 'Action trigger was not found.',
            context: {
              'operation': 'deleteActionTrigger',
              'trigger_id': id,
              'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
              'user_message': 'Gatilho nao encontrado. Atualize a lista e tente novamente.',
            },
          ),
        );
      }

      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to delete action trigger',
          cause: error,
          context: {
            'operation': 'deleteActionTrigger',
            'trigger_id': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<AgentActionExecution>> saveExecution(
    AgentActionExecution execution,
  ) async {
    try {
      final persisted = await _persistExecutionCapturedOutput(execution);
      final row = _mapper.executionToData(persisted);
      await _database.into(_database.agentActionExecutionTable).insertOnConflictUpdate(row);
      return Success(
        await _hydrateExecutionCapturedOutput(
          _mapper.executionFromData(row),
          loadChunkedBodies: true,
        ),
      );
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to save action execution',
          cause: error,
          context: {
            'operation': 'saveActionExecution',
            'execution_id': execution.id,
            'action_id': execution.actionId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async {
    try {
      final row = await (_database.select(
        _database.agentActionExecutionTable,
      )..where((table) => table.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return Failure(
          ActionNotFoundFailure.withContext(
            message: 'Action execution was not found.',
            context: {
              'operation': 'getActionExecution',
              'execution_id': id,
              'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
              'user_message': 'Execucao nao encontrada. Atualize o historico e tente novamente.',
            },
          ),
        );
      }

      return Success(
        await _hydrateExecutionCapturedOutput(
          _mapper.executionFromData(row),
          loadChunkedBodies: hydrateCapturedOutput,
        ),
      );
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to load action execution',
          cause: error,
          context: {
            'operation': 'getActionExecution',
            'execution_id': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    try {
      final query = _database.select(_database.agentActionExecutionTable)
        ..orderBy([
          (table) => OrderingTerm.desc(table.requestedAt),
          (table) => OrderingTerm.asc(table.id),
        ]);
      if (actionId != null) {
        query.where((table) => table.actionId.equals(actionId));
      }
      if (idempotencyKey != null) {
        query.where((table) => table.idempotencyKey.equals(idempotencyKey));
      }
      if (statuses != null && statuses.isNotEmpty) {
        query.where(
          (table) => table.status.isIn(
            statuses.map((status) => status.name).toList(growable: false),
          ),
        );
      }
      if (requestedAfter != null) {
        query.where((table) => table.requestedAt.isBiggerOrEqualValue(requestedAfter));
      }
      if (limit != null) {
        query.limit(limit);
      }

      final rows = await query.get();
      return Success(
        rows.map(_mapper.executionFromData).toList(growable: false),
      );
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to list action executions',
          cause: error,
          context: {
            'operation': 'listActionExecutions',
            'action_id': ?actionId,
            'idempotency_key': ?idempotencyKey,
            'statuses': ?(statuses != null && statuses.isNotEmpty
                ? statuses.map((AgentActionExecutionStatus status) => status.name).toList(growable: false)
                : null),
            'requested_after': ?requestedAfter?.toIso8601String(),
          },
        ),
      );
    }
  }

  @override
  Future<Result<int>> cleanupExecutions({
    required DateTime olderThan,
  }) async {
    try {
      await _capturedOutputChunks.deleteForTerminalExecutionsOlderThan(olderThan);
      final deleted =
          await (_database.delete(_database.agentActionExecutionTable)..where((table) {
                final finishedBeforeRetention = table.finishedAt.isSmallerThanValue(olderThan);
                final requestedBeforeRetention = table.requestedAt.isSmallerThanValue(olderThan);
                final isTerminal = table.status.isIn(
                  AgentActionExecutionStatus.values
                      .where((status) => status.isTerminal)
                      .map((status) => status.name)
                      .toList(growable: false),
                );
                return isTerminal & (finishedBeforeRetention | requestedBeforeRetention);
              }))
              .go();
      return Success(deleted);
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to cleanup action executions',
          cause: error,
          context: {
            'operation': 'cleanupActionExecutions',
            'older_than': olderThan.toIso8601String(),
          },
        ),
      );
    }
  }

  @override
  Future<Result<int>> clearCapturedOutputOlderThan({
    required DateTime olderThan,
  }) async {
    try {
      await _capturedOutputChunks.deleteForTerminalExecutionsOlderThan(olderThan);
      final terminalStatusNames = AgentActionExecutionStatus.values
          .where((AgentActionExecutionStatus status) => status.isTerminal)
          .map((AgentActionExecutionStatus status) => status.name)
          .toList(growable: false);
      final updated =
          await (_database.update(_database.agentActionExecutionTable)..where((table) {
                final finishedBeforeRetention = table.finishedAt.isSmallerThanValue(olderThan);
                final requestedBeforeRetention = table.requestedAt.isSmallerThanValue(olderThan);
                final isTerminal = table.status.isIn(terminalStatusNames);
                final hasCapturedOutput =
                    table.stdoutText.isNotNull() |
                    table.stderrText.isNotNull() |
                    table.stdoutStoredInChunks.equals(true) |
                    table.stderrStoredInChunks.equals(true);
                return isTerminal & (finishedBeforeRetention | requestedBeforeRetention) & hasCapturedOutput;
              }))
              .write(
                const AgentActionExecutionTableCompanion(
                  stdoutText: Value(null),
                  stderrText: Value(null),
                  stdoutTruncated: Value(false),
                  stderrTruncated: Value(false),
                  stdoutStoredInChunks: Value(false),
                  stderrStoredInChunks: Value(false),
                ),
              );
      return Success(updated);
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to clear captured action execution output',
          cause: error,
          context: {
            'operation': 'clearCapturedOutputOlderThan',
            'older_than': olderThan.toIso8601String(),
          },
        ),
      );
    }
  }

  Future<AgentActionExecution> _persistExecutionCapturedOutput(
    AgentActionExecution execution,
  ) async {
    var persisted = execution;
    final stdout = execution.stdoutText;
    if (stdout != null && AgentActionCapturedOutputChunker.shouldSpillToChunks(stdout)) {
      await _capturedOutputChunks.replaceStream(
        executionId: execution.id,
        stream: AgentActionCapturedOutputChunkStore.streamNameForStdout(),
        text: stdout,
      );
      persisted = persisted.copyWith(
        clearStdoutText: true,
        stdoutStoredInChunks: true,
      );
    }
    final stderr = execution.stderrText;
    if (stderr != null && AgentActionCapturedOutputChunker.shouldSpillToChunks(stderr)) {
      await _capturedOutputChunks.replaceStream(
        executionId: execution.id,
        stream: AgentActionCapturedOutputChunkStore.streamNameForStderr(),
        text: stderr,
      );
      persisted = persisted.copyWith(
        clearStderrText: true,
        stderrStoredInChunks: true,
      );
    }
    return persisted;
  }

  @override
  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) async {
    try {
      final window = await _capturedOutputChunks.sliceStreamWindow(
        executionId: executionId,
        stream: stream,
        offsetUtf8: offsetUtf8,
        maxBytes: maxBytes,
      );
      return Success(
        window ??
            (
              text: '',
              nextOffset: offsetUtf8,
              totalBytes: 0,
              responseTruncated: false,
              effectiveStart: offsetUtf8,
            ),
      );
    } on Exception catch (error) {
      return Failure(
        _databaseFailure(
          'Failed to slice captured action execution output',
          cause: error,
          context: {
            'operation': 'sliceCapturedOutput',
            'execution_id': executionId,
            'stream': stream,
          },
        ),
      );
    }
  }

  Future<AgentActionExecution> _hydrateExecutionCapturedOutput(
    AgentActionExecution execution, {
    required bool loadChunkedBodies,
  }) async {
    if (!loadChunkedBodies) {
      return execution;
    }

    var hydrated = execution;
    if (execution.stdoutStoredInChunks) {
      final stdout = await _capturedOutputChunks.loadConcatenatedStream(
        executionId: execution.id,
        stream: AgentActionCapturedOutputChunkStore.streamNameForStdout(),
      );
      hydrated = hydrated.copyWith(stdoutText: stdout);
    }
    if (execution.stderrStoredInChunks) {
      final stderr = await _capturedOutputChunks.loadConcatenatedStream(
        executionId: execution.id,
        stream: AgentActionCapturedOutputChunkStore.streamNameForStderr(),
      );
      hydrated = hydrated.copyWith(stderrText: stderr);
    }
    return hydrated;
  }

  domain.DatabaseFailure _databaseFailure(
    String message, {
    Object? cause,
    Map<String, Object?> context = const {},
  }) {
    return domain.DatabaseFailure.withContext(
      message: message,
      cause: cause,
      context: context,
    );
  }
}
