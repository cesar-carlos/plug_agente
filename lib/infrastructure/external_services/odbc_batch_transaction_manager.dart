import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
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

  static const Duration _defaultRollbackTimeout = Duration(seconds: 15);

  /// Begins a transaction when [transactionEnabled]; otherwise returns a
  /// non-transactional start (null id).
  Future<Result<BatchTransactionStart>> beginIfNeeded({
    required String connectionId,
    required bool transactionEnabled,
    required Duration? lockTimeout,
    required TransactionAccessMode accessMode,
  }) async {
    if (!transactionEnabled) {
      return const Success(BatchTransactionStart(null));
    }

    final beginResult = await _service.beginTransaction(
      connectionId,
      savepointDialect: SavepointDialect.auto,
      accessMode: accessMode,
      lockTimeout: lockTimeout,
    );
    if (beginResult.isError()) {
      final error = beginResult.exceptionOrNull()!;
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

    return Success(BatchTransactionStart(beginResult.getOrNull()));
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

    final commitResult = await _service.commitTransaction(
      connectionId,
      transactionId,
    );
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
    if (deadline == null) {
      return _rollbackTimeout;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return _rollbackTimeout;
    }
    return remaining < _rollbackTimeout ? remaining : _rollbackTimeout;
  }
}
