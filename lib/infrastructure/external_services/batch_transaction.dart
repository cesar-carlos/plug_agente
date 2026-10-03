import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Result of (optionally) starting a batch transaction: carries the engine
/// transaction id, or null when the batch is non-transactional.
class BatchTransactionStart {
  const BatchTransactionStart(this.transactionId);

  final int? transactionId;
}

/// Tracks the lifecycle of a batch transaction so it is rolled back at most
/// once and never after a successful commit.
enum BatchTransactionState { active, completing, committed, rollingBack, rolledBack, unconfirmed }

class BatchTransactionGuard {
  BatchTransactionGuard(this.transactionId);

  final int? transactionId;
  BatchTransactionState _state = BatchTransactionState.active;
  Object? rollbackError;

  BatchTransactionState get state => _state;
  bool get isActive => transactionId != null && _state == BatchTransactionState.active;
  bool get rollbackConfirmed => _state == BatchTransactionState.rolledBack;

  bool beginCompletion() {
    if (!isActive) return false;
    _state = BatchTransactionState.completing;
    return true;
  }

  void markUnconfirmed() => _state = BatchTransactionState.unconfirmed;

  /// Invokes [rollback] for the active transaction id exactly once, marking the
  /// guard closed. No-op when there is no transaction or it is already closed.
  Future<Result<void>> rollback(
    Future<Result<void>> Function(int transactionId) rollback,
  ) async {
    final id = transactionId;
    if (id == null || !isActive) return const Success(unit);
    _state = BatchTransactionState.rollingBack;
    try {
      final result = await rollback(id);
      rollbackError = result.exceptionOrNull();
      _state = result.isSuccess() ? BatchTransactionState.rolledBack : BatchTransactionState.unconfirmed;
      return result;
    } on Object catch (error) {
      rollbackError = error;
      markUnconfirmed();
      return Failure(domain.QueryExecutionFailure.withContext(message: 'Rollback was not confirmed', cause: error, context: const {'outcome_unknown': true, 'retryable': false}));
    }
  }

  void markCommitted() {
    _state = BatchTransactionState.committed;
  }
}
