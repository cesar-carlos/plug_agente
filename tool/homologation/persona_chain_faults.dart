import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:result_dart/result_dart.dart';

// Fixture-only fault: actual native commit succeeds before its confirmation is
// deliberately lost. Every SQL/identity/transaction call uses the real adapter.
class ChainCommitFaultFactory implements ISqlOperationTransactionFactory {
  ChainCommitFaultFactory(this.delegate);
  final ISqlOperationTransactionFactory delegate;
  bool loseNextConfirmation = false;
  @override
  Future<Result<ISqlOperationTransaction>> open(
    SqlOperationTarget target,
    Duration timeout, {
    SqlOperationPlan? plan,
  }) async {
    final opened = await delegate.open(target, timeout, plan: plan);
    if (opened.isError() || !loseNextConfirmation) return opened;
    loseNextConfirmation = false;
    return Success(_LostCommitConfirmation(opened.getOrThrow()));
  }
}

class _LostCommitConfirmation implements ISqlOperationTransaction {
  const _LostCommitConfirmation(this.delegate);
  final ISqlOperationTransaction delegate;
  @override
  Result<void> validatePlan(SqlOperationPlan plan) => delegate.validatePlan(plan);
  @override
  Future<Result<SqlOperationStepResult>> execute(
    SqlOperationStep step,
    Map<String, SqlScalar> parameters,
    Duration timeout,
  ) => delegate.execute(step, parameters, timeout);
  @override
  Future<Result<void>> commit(Duration timeout) async {
    final committed = await delegate.commit(timeout);
    if (committed.isError()) return committed;
    return Failure(
      SqlOperationFailure(
        code: 'SQL_OPERATION_NATIVE_FAILED',
        message: 'Private fixture lost native commit confirmation.',
        context: const {'outcome_unknown': true, 'retryable': false, 'stage': 'commit'},
      ),
    );
  }

  @override
  Future<Result<void>> rollback(Duration timeout) => delegate.rollback(timeout);
  @override
  Future<Result<void>> close() => delegate.close();
}
