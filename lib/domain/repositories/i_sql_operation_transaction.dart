import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class ISqlOperationAuthorizer {
  Future<Result<SqlOperationTarget>> authorize(
    SqlOperationReference reference,
    String token,
    String agentId,
    List<SqlOperationStep> steps,
  );
}

abstract interface class ISqlOperationTransactionFactory {
  Future<Result<ISqlOperationTransaction>> open(SqlOperationTarget target, Duration timeout, {SqlOperationPlan? plan});
}

abstract interface class ISqlOperationTransaction {
  Result<void> validatePlan(SqlOperationPlan plan);
  Future<Result<SqlOperationStepResult>> execute(
    SqlOperationStep step,
    Map<String, SqlScalar> parameters,
    Duration timeout,
  );
  Future<Result<void>> commit(Duration timeout);
  Future<Result<void>> rollback(Duration timeout);
  Future<Result<void>> close();
}
