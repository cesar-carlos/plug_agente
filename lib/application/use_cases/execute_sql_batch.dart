import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// Executes a batch of SQL commands.
///
/// Each command is executed independently and results are returned per command.
/// Optionally supports transactional execution (all-or-nothing).
class ExecuteSqlBatch {
  ExecuteSqlBatch(
    this._databaseGateway,
    this._normalizerService,
  );

  final IDatabaseGateway _databaseGateway;
  final QueryNormalizerService _normalizerService;

  Future<Result<List<SqlCommandResult>>> call(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions? options,
    Duration? timeout,
    String? sourceRpcRequestId,
  }) async {
    final opts = options ?? const SqlExecutionOptions();

    if (opts.transaction) {
      for (var i = 0; i < commands.length; i++) {
        final validation = SqlValidator.validateSqlForExecution(commands[i].sql);
        if (validation.isError()) {
          final failure = validation.exceptionOrNull()! as domain.Failure;
          return Failure(
            domain.ValidationFailure.withContext(
              message: 'Invalid SQL in transactional batch at index $i: ${failure.message}',
              context: {
                'operation': 'batch_validation',
                'index': i,
                'reason': failure.context['reason'] ?? SqlPipelineContextConstants.invalidSqlReason,
              },
            ),
          );
        }
      }
      return _databaseGateway.executeBatch(
        agentId,
        commands,
        database: database,
        options: opts,
        timeout: timeout,
        sourceRpcRequestId: sourceRpcRequestId,
      );
    }

    final batchResult = await _databaseGateway.executeBatch(
      agentId,
      commands,
      database: database,
      options: opts,
      timeout: timeout,
      sourceRpcRequestId: sourceRpcRequestId,
    );
    return batchResult.fold(
      (results) => Success(
        results.map((result) => _normalizeNonTransactionalResult(result, opts)).toList(growable: false),
      ),
      Failure.new,
    );
  }

  SqlCommandResult _normalizeNonTransactionalResult(
    SqlCommandResult result,
    SqlExecutionOptions options,
  ) {
    final rows = result.rows;
    if (!result.ok || rows == null) {
      return result;
    }

    final limitedRows = _normalizerService.normalizeRows(
      truncateSqlResultRows(rows, options.maxRows),
    );

    return SqlCommandResult.success(
      index: result.index,
      rows: limitedRows,
      rowCount: limitedRows.length,
      affectedRows: result.affectedRows,
      columnMetadata: result.columnMetadata,
    );
  }
}
