import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/logging/odbc_resilience_log.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Owns the ODBC transaction lifecycle for batch execution: begin, commit and
/// bounded rollback.
///
/// Extracted from `OdbcDatabaseGateway` so transaction begin/commit/rollback
/// semantics (including the rollback time budget and rollback-on-commit-failure
/// behavior) live behind a focused, testable surface.
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

    final skipOptions =
        connectionString != null && _plainTransactionConnectionStrings.contains(connectionString);
    final beginResult = await _beginTransaction(
      connectionId,
      accessMode: skipOptions ? TransactionAccessMode.readWrite : accessMode,
      lockTimeout: skipOptions ? null : lockTimeout,
      deadline: deadline,
    );
    if (beginResult.isError()) {
      final error = beginResult.exceptionOrNull()!;
      if (error is UnsupportedFeatureError && !skipOptions) {
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
    final budget = _boundedBudget(deadline, _defaultBeginTimeout);
    try {
      return await _service
          .beginTransaction(
            connectionId,
            savepointDialect: SavepointDialect.auto,
            accessMode: accessMode,
            lockTimeout: lockTimeout,
          )
          .timeout(budget);
    } on TimeoutException catch (error) {
      _onRollbackUnconfirmed?.call(connectionId);
      return Failure(error);
    }
  }

  Result<BatchTransactionStart> _beginFailure(Object error) {
    if (error is TimeoutException) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Timed out while starting the transaction',
          cause: error,
          context: {
            'reason': OdbcContextConstants.transactionFailedReason,
            'operation': 'transaction_begin',
            'timeout': true,
            'timeout_stage': 'sql',
            'retryable': true,
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

  /// Commits the [guard]'s transaction, rolling back on commit failure.
  Future<Result<void>> commit({
    required String connectionId,
    required BatchTransactionGuard guard,
    DateTime? deadline,
  }) async {
    final transactionId = guard.transactionId;
    if (transactionId == null) {
      return const Success(unit);
    }

    late Result<void> commitResult;
    try {
      commitResult = await _service
          .commitTransaction(
            connectionId,
            transactionId,
          )
          .timeout(_boundedBudget(deadline, _defaultCommitTimeout));
    } on TimeoutException catch (error) {
      _metrics.recordTransactionCommitUnconfirmed();
      _onRollbackUnconfirmed?.call(connectionId);
      OdbcResilienceLog.warning(
        event: 'commit_unconfirmed',
        reason: OdbcContextConstants.transactionCommitUnconfirmedReason,
        stage: 'transaction_commit',
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Transaction commit was not confirmed before the deadline',
          cause: error,
          context: {
            'reason': OdbcContextConstants.transactionCommitUnconfirmedReason,
            'operation': 'transaction_commit',
            'timeout': true,
            'timeout_stage': 'sql',
          },
        ),
      );
    }
    if (commitResult.isError()) {
      final error = commitResult.exceptionOrNull()!;
      final rollbackTimeout = rollbackTimeoutFromDeadline(deadline);
      await guard.rollback(
        (id) => rollbackIfNeeded(connectionId, id, timeout: rollbackTimeout),
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Failed to commit transaction',
          cause: error,
          context: {
            'reason': OdbcContextConstants.transactionFailedReason,
            'operation': 'transaction_commit',
            'error': OdbcErrorInspector.message(error),
          },
        ),
      );
    }

    guard.markCommitted();
    return const Success(unit);
  }

  /// Best-effort rollback bounded by [timeout]. Logs and records metrics on
  /// failure/timeout; the caller is expected to discard the connection when the
  /// rollback could not be confirmed.
  Future<void> rollbackIfNeeded(
    String connectionId,
    int? transactionId, {
    Duration? timeout,
  }) async {
    if (transactionId == null) {
      return;
    }
    final effectiveTimeout = timeout ?? _rollbackTimeout;
    _metrics.recordTransactionRollbackAttempt();
    try {
      final rollback = await _service.rollbackTransaction(connectionId, transactionId).timeout(effectiveTimeout);
      if (rollback.isError()) {
        _metrics.recordTransactionRollbackFailure();
        developer.log(
          'Failed to rollback transaction',
          name: 'database_gateway',
          level: 900,
          error: rollback.exceptionOrNull(),
        );
        _onRollbackUnconfirmed?.call(connectionId);
      }
    } on TimeoutException catch (error) {
      _metrics.recordTransactionRollbackFailure();
      developer.log(
        'Rollback timed out after ${effectiveTimeout.inSeconds}s; connection will be discarded',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      _onRollbackUnconfirmed?.call(connectionId);
    }
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
}
