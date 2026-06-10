import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:result_dart/result_dart.dart';

/// Validates every SQL command in a batch before execution.
///
/// Uses fail-fast semantics: the first invalid command stops validation.
class ValidateSqlBatch {
  const ValidateSqlBatch();

  Result<void> call(List<SqlCommand> commands) {
    for (var i = 0; i < commands.length; i++) {
      final validation = SqlValidator.validateSqlForExecution(commands[i].sql);
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()! as domain.Failure;
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Invalid SQL in batch at index $i: ${failure.message}',
            context: {
              'operation': 'batch_validation',
              'index': i,
              'reason': failure.context['reason'] ?? SqlPipelineContextConstants.invalidSqlReason,
            },
          ),
        );
      }
    }
    return const Success(unit);
  }
}
