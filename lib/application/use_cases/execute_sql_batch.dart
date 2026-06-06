import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/validate_sql_batch.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// Executes a batch of SQL commands.
///
/// Each command is executed independently and results are returned per command.
/// Optionally supports transactional execution (all-or-nothing).
class ExecuteSqlBatch {
  ExecuteSqlBatch(
    this._databaseGateway,
    this._normalizerService, {
    ValidateSqlBatch? validateSqlBatch,
    int Function()? poolSizeProvider,
  }) : _validateSqlBatch = validateSqlBatch ?? const ValidateSqlBatch(),
       _poolSizeProvider = poolSizeProvider ?? _defaultPoolSize;

  static int _defaultPoolSize() => ConnectionConstants.poolSize;

  final IDatabaseGateway _databaseGateway;
  final QueryNormalizerService _normalizerService;
  final ValidateSqlBatch _validateSqlBatch;
  final int Function() _poolSizeProvider;

  Future<Result<List<SqlCommandResult>>> call(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions? options,
    Duration? timeout,
    String? sourceRpcRequestId,
  }) async {
    final validation = _validateSqlBatch(commands);
    if (validation.isError()) {
      return Failure(validation.exceptionOrNull()!);
    }

    final opts = _capReadOnlyBatchParallelism(options ?? const SqlExecutionOptions());

    if (opts.transaction) {
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

  SqlExecutionOptions _capReadOnlyBatchParallelism(SqlExecutionOptions options) {
    if (options.transaction || options.maxParallelReadOnlyBatchItems <= 1) {
      return options;
    }
    final cap = ConnectionConstants.readOnlyBatchParallelismForPoolSize(_poolSizeProvider());
    if (options.maxParallelReadOnlyBatchItems <= cap) {
      return options;
    }
    return SqlExecutionOptions(
      timeoutMs: options.timeoutMs,
      maxRows: options.maxRows,
      transaction: options.transaction,
      maxParallelReadOnlyBatchItems: cap,
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
