import 'dart:async';

import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_journal.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:plug_agente/domain/services/i_update_maintenance_gate.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// One durable claim, one connection, one transaction. Never retries dispatch or commit.
class SqlOperationExecutor {
  SqlOperationExecutor({
    required ISqlOperationJournal journal,
    required ISqlOperationAuthorizer authorizer,
    required ISqlOperationTransactionFactory transactions,
    IUpdateMaintenanceGate? maintenanceGate,
    DateTime Function()? now,
    Uuid uuid = const Uuid(),
    void Function(String operationId, Object failure)? onCleanupFailure,
  }) : _maintenanceGate = maintenanceGate,
       _journal = journal,
       _authorizer = authorizer,
       _transactions = transactions,
       _now = now ?? DateTime.now,
       _uuid = uuid,
       _onCleanupFailure = onCleanupFailure;
  final IUpdateMaintenanceGate? _maintenanceGate;
  final ISqlOperationJournal _journal;
  final ISqlOperationAuthorizer _authorizer;
  final ISqlOperationTransactionFactory _transactions;
  final DateTime Function() _now;
  final Uuid _uuid;
  final void Function(String, Object)? _onCleanupFailure;

  Future<Result<SqlOperationJournalEntry>> execute(SqlOperationPlan plan, String token, String agentId) =>
      _maintenanceGate?.run(() => _execute(plan, token, agentId)) ?? _execute(plan, token, agentId);

  Future<Result<SqlOperationJournalEntry>> _execute(SqlOperationPlan plan, String token, String agentId) async {
    final watch = Stopwatch()..start();
    Duration budget() {
      final remaining = plan.timeout - watch.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('SQL operation budget exhausted');
      return remaining;
    }

    ISqlOperationTransaction? transaction;
    SqlOperationTarget? target;
    var claimed = false;
    var commitAttempted = false;
    var total = 0;
    try {
      target = (await _authorizer.authorize(plan, token, agentId, plan.steps).timeout(budget())).getOrThrow();
      final claim = (await _journal.claim(
        SqlOperationJournalEntry(
          operationId: plan.operationId,
          scopeHash: target.scopeHash,
          fingerprint: plan.fingerprint,
          contentHash: plan.contentHash,
          executionId: _uuid.v4(),
          state: SqlOperationJournalState.executing,
          updatedAt: _now(),
        ),
      )).getOrThrow();
      if (!claim.claimed) return Success(claim.entry);
      claimed = true;
      // Intent is durable before open/begin and before any business statement.
      // The factory owns timeout/late-connect cleanup; never abandon its future here.
      transaction = (await _transactions.open(target, budget())).getOrThrow();
      transaction.validatePlan(plan).getOrThrow();
      final values = <String, Map<String, SqlScalar>>{};
      for (final step in plan.steps) {
        await _assertCurrent(plan, token, agentId, target, budget());
        final parameters = <String, SqlScalar>{};
        for (final entry in step.params.entries) {
          parameters[entry.key] = switch (entry.value) {
            SqlOperationValue(:final scalar) => scalar,
            SqlOperationOutput(:final stepId, :final output) => values[stepId]![output]!,
          };
        }
        final result = (await transaction.execute(step, parameters, budget())).getOrThrow();
        final expected = step.expectedRows;
        if (expected != null && !expected.contains(result.rows.length)) {
          throw _failure('SQL_OPERATION_CONDITION_FAILED', 'A trained row condition failed.');
        }
        if (step.effect != SqlOperationEffect.select) {
          final count = result.directlyAffectedRows;
          if (count == null || count < 0 || step.affectedRows == null || !step.affectedRows!.contains(count)) {
            throw _failure('SQL_OPERATION_ROW_LIMIT', 'Direct affected-row count is unknown or outside its bounds.');
          }
          total += count;
          if (total > plan.maxAffectedRows) throw _failure('SQL_OPERATION_ROW_LIMIT', 'Operation row limit exceeded.');
        }
        if (step.outputs.isNotEmpty) {
          if (result.rows.length != 1) {
            throw _failure('SQL_OPERATION_OUTPUT_INVALID', 'Scalar outputs require exactly one row.');
          }
          values[step.id] = {
            for (final output in step.outputs.entries)
              output.key: _scalar(
                output.value,
                result.rows.single[output.key],
                result.rows.single.containsKey(output.key),
              ),
          };
        }
      }
      await _assertCurrent(plan, token, agentId, target, budget());
      commitAttempted = true;
      (await transaction.commit(budget())).getOrThrow();
      return await _journal.finish(
        plan.operationId,
        target.scopeHash,
        plan.fingerprint,
        SqlOperationJournalState.completed,
        directlyAffectedRows: total,
      );
    } on Object catch (error) {
      if (!claimed || target == null) return Failure(_asFailure(error));
      // A timed-out native call may still be running. Do not issue concurrent rollback.
      var state = SqlOperationJournalState.outcomeUnknown;
      if (!commitAttempted && !_isUnknown(error)) {
        if (transaction == null) {
          state = SqlOperationJournalState.cancelled;
        } else {
          try {
            final rollback = await transaction.rollback(const Duration(seconds: 15));
            if (rollback.isSuccess()) {
              state = SqlOperationJournalState.rolledBack;
            } else {
              _onCleanupFailure?.call(plan.operationId, rollback.exceptionOrNull()!);
            }
          } on Object catch (failure) {
            _onCleanupFailure?.call(plan.operationId, failure);
          }
        }
      }
      return await _journal.finish(plan.operationId, target.scopeHash, plan.fingerprint, state);
    } finally {
      watch.stop();
      if (transaction != null) {
        try {
          final closed = await transaction.close();
          if (closed.isError()) _onCleanupFailure?.call(plan.operationId, closed.exceptionOrNull()!);
        } on Object catch (error) {
          _onCleanupFailure?.call(plan.operationId, error);
        }
      }
    }
  }

  Future<Result<SqlOperationJournalEntry>> get(SqlOperationReference reference, String token, String agentId) =>
      _maintenanceGate?.run(() => _get(reference, token, agentId)) ?? _get(reference, token, agentId);

  Future<Result<SqlOperationJournalEntry>> _get(SqlOperationReference reference, String token, String agentId) async {
    try {
      final target =
          (await _authorizer.authorize(reference, token, agentId, const []).timeout(const Duration(seconds: 15)))
              .getOrThrow();
      return await _journal.get(reference.operationId, target.scopeHash, reference.fingerprint);
    } on Object catch (error) {
      return Failure(_asFailure(error));
    }
  }

  Future<Result<SqlOperationJournalEntry>> cancel(SqlOperationReference reference, String token, String agentId) =>
      _maintenanceGate?.run(() => _cancel(reference, token, agentId)) ?? _cancel(reference, token, agentId);

  Future<Result<SqlOperationJournalEntry>> _cancel(
    SqlOperationReference reference,
    String token,
    String agentId,
  ) async {
    try {
      final target =
          (await _authorizer.authorize(reference, token, agentId, const []).timeout(const Duration(seconds: 15)))
              .getOrThrow();
      return await _journal.requestCancellation(reference.operationId, target.scopeHash, reference.fingerprint);
    } on Object catch (error) {
      return Failure(_asFailure(error));
    }
  }

  Future<void> _assertCurrent(
    SqlOperationPlan plan,
    String token,
    String agentId,
    SqlOperationTarget original,
    Duration timeout,
  ) async {
    final current = (await _authorizer.authorize(plan, token, agentId, plan.steps).timeout(timeout)).getOrThrow();
    if (current.authorizationHash != original.authorizationHash || current.scopeHash != original.scopeHash) {
      throw _failure('SQL_OPERATION_AUTHORIZATION_CHANGED', 'Authorization or physical source changed.');
    }
    final entry = (await _journal.get(plan.operationId, original.scopeHash, plan.fingerprint)).getOrThrow();
    if (entry.state != SqlOperationJournalState.executing) {
      throw _failure('SQL_OPERATION_CANCELLED', 'Cancellation requested or operation no longer active.');
    }
  }

  static SqlScalar _scalar(SqlScalarType type, Object? value, bool exists) {
    if (!exists) throw _failure('SQL_OPERATION_OUTPUT_INVALID', 'Declared scalar output is missing.');
    final converted = switch (type) {
      SqlScalarType.integer when value is int => value.toString(),
      SqlScalarType.integer when value is String && RegExp(r'^-?\d+$').hasMatch(value) => value,
      SqlScalarType.decimal when value is String && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value) => value,
      SqlScalarType.decimal when value is int => value.toString(),
      SqlScalarType.string when value is String => value,
      SqlScalarType.uuid when value is String && Uuid.isValidUUID(fromString: value) => value,
      SqlScalarType.date when value is DateTime => value.toUtc().toIso8601String(),
      SqlScalarType.date when value is String && DateTime.tryParse(value) != null => value,
      SqlScalarType.boolean when value is bool => value,
      SqlScalarType.nullValue when value == null => null,
      _ => throw _failure('SQL_OPERATION_OUTPUT_INVALID', 'Scalar output type cannot be preserved exactly.'),
    };
    return SqlScalar(type, converted);
  }

  static bool _isUnknown(Object error) =>
      error is TimeoutException || (error is domain.Failure && error.context['outcome_unknown'] == true);
  static SqlOperationFailure _failure(String code, String message) => SqlOperationFailure(code: code, message: message);
  static Exception _asFailure(Object error) => error is Exception
      ? error
      : SqlOperationFailure(code: 'SQL_OPERATION_FAILED', message: 'SQL operation failed.', cause: error);
}
