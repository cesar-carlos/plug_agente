import 'dart:async';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Owns the ODBC transaction lifecycle for batch execution: begin, commit and
/// bounded rollback.
///
/// Extracted from `OdbcDatabaseGateway` so transaction begin/commit/rollback
/// semantics (including bounded cleanup and uncertain completion) live behind a focused, testable surface.
final class OdbcBatchTransactionManager {
  OdbcBatchTransactionManager({
    required OdbcService service,
    required MetricsCollector metrics,
    Duration rollbackTimeout = _defaultRollbackTimeout,
    void Function(String connectionId)? onRollbackUnconfirmed,
  }) : _service = service,
       _metrics = metrics,
       _rollbackTimeout = rollbackTimeout,
       _onRollbackUnconfirmed = onRollbackUnconfirmed;

  final OdbcService _service;
  final MetricsCollector _metrics;
  final Duration _rollbackTimeout;
  final void Function(String connectionId)? _onRollbackUnconfirmed;
  final Set<String> _plainTransactionConnectionStrings = <String>{};

  static const Duration _defaultRollbackTimeout = Duration(seconds: 15);
  static const Duration _defaultBeginTimeout = Duration(seconds: 15);
  static const Duration _defaultCommitTimeout = Duration(seconds: 15);

  /// Begins a transaction when [transactionEnabled]; otherwise returns a
  /// non-transactional start (null id).
  Future<Result<BatchTransactionStart>> beginIfNeeded({
    required String connectionId,
    required bool transactionEnabled,
    required Duration? lockTimeout,
    required TransactionAccessMode accessMode,
    String? connectionString,
    DateTime? deadline,
  }) async {
    if (!transactionEnabled) {
      return const Success(BatchTransactionStart(null));
    }

    final skipOptions = connectionString != null && _plainTransactionConnectionStrings.contains(connectionString);
    final beginResult = await _beginTransaction(
      connectionId,
      accessMode: skipOptions ? TransactionAccessMode.readWrite : accessMode,
      lockTimeout: skipOptions ? null : lockTimeout,
      deadline: deadline,
    );
    if (beginResult.isError()) {
      final error = beginResult.exceptionOrNull()!;
      if (!OdbcErrorInspector.outcomeUnknown(error) && error is UnsupportedFeatureError && !skipOptions) {
        _metrics.recordTransactionOptionsUnsupported();
        if (connectionString != null) {
          _plainTransactionConnectionStrings.add(connectionString);
        }
        final plainBegin = await _beginTransaction(
          connectionId,
          accessMode: TransactionAccessMode.readWrite,
          lockTimeout: null,
          deadline: deadline,
        );
        if (plainBegin.isSuccess()) {
          return Success(BatchTransactionStart(plainBegin.getOrNull()));
        }
        return _beginFailure(plainBegin.exceptionOrNull()!);
      }
      return _beginFailure(error);
    }

    return Success(BatchTransactionStart(beginResult.getOrNull()));
  }

  Future<Result<int>> _beginTransaction(
    String connectionId, {
    required TransactionAccessMode accessMode,
    required Duration? lockTimeout,
    required DateTime? deadline,
  }) async {
    final budget = _executionBudget(deadline, _defaultBeginTimeout);
    if (budget <= Duration.zero) {
      return Failure(_budgetExhausted('transaction_begin'));
    }
    try {
      final result = await _service
          .beginTransaction(
            connectionId,
            savepointDialect: SavepointDialect.auto,
            accessMode: accessMode,
            lockTimeout: lockTimeout,
          )
          .timeout(budget);
      if (result.isError() && OdbcErrorInspector.outcomeUnknown(result.exceptionOrNull()!)) {
        _onRollbackUnconfirmed?.call(connectionId);
      }
      return result;
    } on TimeoutException catch (error) {
      _onRollbackUnconfirmed?.call(connectionId);
      return Failure(error);
    } on Object catch (error) {
      if (OdbcErrorInspector.outcomeUnknown(error)) _onRollbackUnconfirmed?.call(connectionId);
      return Failure(OdbcFailureMapper.mapQueryError(error, operation: 'transaction_begin'));
    }
  }

  Result<BatchTransactionStart> _beginFailure(Object error) {
    if (error is domain.Failure && error.context['execution_not_started'] == true) {
      return Failure(error);
    }
    if (OdbcErrorInspector.outcomeUnknown(error) || error is TimeoutException) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Timed out while starting the transaction',
          cause: error,
          context: {
            'reason': OdbcContextConstants.transactionFailedReason,
            'operation': 'transaction_begin',
            'timeout': true,
            'timeout_stage': 'sql',
            'retryable': false,
            'outcome_unknown': true,
          },
        ),
      );
    }
    final isUnsupportedFeature = error is UnsupportedFeatureError;
    return Failure(
      domain.QueryExecutionFailure.withContext(
        message: isUnsupportedFeature
            ? 'Transaction options are not supported by the ODBC runtime'
            : 'Failed to start transaction',
        cause: error,
        context: {
          'reason': isUnsupportedFeature
              ? OdbcContextConstants.unsupportedOdbcFeatureReason
              : OdbcContextConstants.transactionFailedReason,
          'operation': 'transaction_begin',
          'error': OdbcErrorInspector.message(error),
          'retryable': false,
          if (isUnsupportedFeature)
            'user_message':
                'The database transaction options (access mode or lock timeout) '
                'are not supported by the loaded ODBC runtime.',
        },
      ),
    );
  }

  Future<Result<void>> commit({
    required String connectionId,
    required BatchTransactionGuard guard,
    DateTime? deadline,
  }) async {
    final transactionId = guard.transactionId;
    if (transactionId == null) return const Success(unit);
    final budget = _executionBudget(deadline, _defaultCommitTimeout);
    if (budget <= Duration.zero) return Failure(_budgetExhausted('transaction_commit'));
    if (!guard.beginCompletion()) {
      return Failure(domain.QueryExecutionFailure('Transaction finalization already started'));
    }
    Object? failure;
    try {
      final result = await _service.commitTransaction(connectionId, transactionId).timeout(budget);
      if (result.isSuccess()) {
        guard.markCommitted();
        return const Success(unit);
      }
      failure = result.exceptionOrNull()!;
    } on Object catch (error) {
      failure = error;
    }
    // Never reverse a commit decision, including failures returned as Result.
    guard.markUnconfirmed();
    _metrics.recordTransactionCommitUnconfirmed();
    _onRollbackUnconfirmed?.call(connectionId);
    final mapped = OdbcFailureMapper.mapQueryError(failure, operation: 'transaction_commit');
    return Failure(
      domain.QueryExecutionFailure.withContext(
        message: 'Transaction commit was not confirmed',
        cause: failure,
        context: {
          ...mapped.context,
          'reason': OdbcContextConstants.transactionCommitUnconfirmedReason,
          'operation': 'transaction_commit',
          'odbc_transaction_id': transactionId.toString(),
          'odbc_connection_id': connectionId,
          'outcome_unknown': true,
          'retryable': false,
          if (OdbcErrorInspector.isTimeout(failure)) ...{'timeout': true, 'timeout_stage': 'sql'},
          'user_message': 'O banco não confirmou o commit. Verifique a transação antes de tentar novamente.',
        },
      ),
    );
  }

  Future<Result<void>> rollbackIfNeeded(
    String connectionId,
    int? transactionId, {
    Duration? timeout,
  }) async {
    if (transactionId == null) return const Success(unit);
    _metrics.recordTransactionRollbackAttempt();
    Object? failure;
    try {
      final result = await _service
          .rollbackTransaction(connectionId, transactionId)
          .timeout(timeout ?? _rollbackTimeout);
      if (result.isSuccess()) return const Success(unit);
      failure = result.exceptionOrNull()!;
    } on Object catch (error) {
      failure = error;
    }
    _metrics.recordTransactionRollbackFailure();
    _onRollbackUnconfirmed?.call(connectionId);
    final mapped = OdbcFailureMapper.mapQueryError(failure, operation: 'transaction_rollback');
    return Failure(
      domain.QueryExecutionFailure.withContext(
        message: 'Transaction rollback was not confirmed',
        cause: failure,
        context: {
          ...mapped.context,
          'operation': 'transaction_rollback',
          'outcome_unknown': true,
          'retryable': false,
        },
      ),
    );
  }

  /// Remaining time from [deadline] clamped to the configured rollback timeout;
  /// falls back to the full rollback timeout when no deadline is set or it has
  /// already elapsed.
  Duration rollbackTimeoutFromDeadline(DateTime? deadline) {
    return _boundedBudget(deadline, _rollbackTimeout);
  }

  Duration _boundedBudget(DateTime? deadline, Duration fallback) {
    if (deadline == null) {
      return fallback;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return fallback;
    }
    return remaining < fallback ? remaining : fallback;
  }

  Duration _executionBudget(DateTime? deadline, Duration fallback) {
    if (deadline == null) return fallback;
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : (remaining < fallback ? remaining : fallback);
  }

  domain.QueryExecutionFailure _budgetExhausted(String operation) => domain.QueryExecutionFailure.withContext(
    message: 'Operation budget exhausted before transaction dispatch',
    context: {
      'operation': operation,
      'timeout': true,
      'timeout_stage': 'sql',
      'execution_not_started': true,
      'retryable': false,
    },
  );
}
