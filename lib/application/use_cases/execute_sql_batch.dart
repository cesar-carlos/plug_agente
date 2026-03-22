import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Executes a batch of SQL commands.
///
/// Each command is executed independently and results are returned per command.
/// Optionally supports transactional execution (all-or-nothing).
class ExecuteSqlBatch {
  ExecuteSqlBatch(
    this._databaseGateway,
    this._normalizerService,
    this._uuid,
  );

  final IDatabaseGateway _databaseGateway;
  final QueryNormalizerService _normalizerService;
  final Uuid _uuid;

  Future<Result<List<SqlCommandResult>>> call(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions? options,
    Duration? timeout,
  }) async {
    final opts = options ?? const SqlExecutionOptions();
    final batchDeadline = timeout == null ? null : DateTime.now().add(timeout);

    if (opts.transaction) {
      return _databaseGateway.executeBatch(
        agentId,
        commands,
        database: database,
        options: opts,
        timeout: timeout,
      );
    }

    // Validate all commands first
    final validationResults = <int, domain.Failure>{};
    for (var i = 0; i < commands.length; i++) {
      final validation = SqlValidator.validateSqlForExecution(commands[i].sql);
      if (validation.isError()) {
        validationResults[i] = validation.exceptionOrNull()! as domain.Failure;
      }
    }

    if (validationResults.isEmpty && commands.length > 1) {
      final batchResult = await _databaseGateway.executeBatch(
        agentId,
        commands,
        database: database,
        options: opts,
        timeout: timeout,
      );
      return batchResult.fold(
        (List<SqlCommandResult> commandResults) => Success(
          _normalizeBatchResults(commandResults, opts),
        ),
        Failure.new,
      );
    }

    // Execute commands
    final results = <SqlCommandResult>[];

    for (var i = 0; i < commands.length; i++) {
      // Skip if validation failed (non-transaction mode)
      if (validationResults.containsKey(i)) {
        final failure = validationResults[i]!;
        final errorMessage = failure.message;

        results.add(
          SqlCommandResult.failure(
            index: i,
            error: errorMessage,
          ),
        );
        continue;
      }

      Duration? perCommandTimeout;
      if (batchDeadline != null) {
        final remaining = batchDeadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Batch execution budget exhausted before database call',
              context: {
                'timeout': true,
                'timeout_stage': 'sql',
                'stage': 'batch',
                'reason': 'batch_budget_exhausted',
                'failedIndex': i,
              },
            ),
          );
        }
        perCommandTimeout = remaining;
      }

      // Execute command
      final command = commands[i];
      final request = queryRequestForCommand(
        command,
        agentId: agentId,
        requestId: _uuid.v4(),
      );
      final executeResult = switch ((perCommandTimeout, database)) {
        (null, null) => await _databaseGateway.executeQuery(request),
        (null, final db?) => await _databaseGateway.executeQuery(
          request,
          database: db,
        ),
        (final t?, null) => await _databaseGateway.executeQuery(
          request,
          timeout: t,
        ),
        (final t?, final db?) => await _databaseGateway.executeQuery(
          request,
          timeout: t,
          database: db,
        ),
      };

      executeResult.fold(
        (response) {
          final normalized = _normalizerService.normalize(response);
          final limitedRows = truncateSqlResultRows(
            normalized.data,
            opts.maxRows,
          );

          results.add(
            SqlCommandResult.success(
              index: i,
              rows: limitedRows,
              rowCount: limitedRows.length,
              affectedRows: normalized.affectedRows,
              columnMetadata: normalized.columnMetadata,
            ),
          );
        },
        (failure) {
          final domainFailure = failure as domain.Failure;
          results.add(
            SqlCommandResult.failure(
              index: i,
              error: domainFailure.message,
            ),
          );
        },
      );
    }

    return Success(results);
  }

  List<SqlCommandResult> _normalizeBatchResults(
    List<SqlCommandResult> results,
    SqlExecutionOptions options,
  ) {
    return results
        .map((SqlCommandResult result) {
          if (!result.ok || result.rows == null) {
            return result;
          }

          final normalized = _normalizerService.normalize(
            QueryResponse(
              id: 'batch-${result.index}',
              requestId: 'batch-${result.index}',
              agentId: 'batch',
              data: result.rows!,
              affectedRows: result.affectedRows,
              timestamp: DateTime.now(),
              columnMetadata: result.columnMetadata,
            ),
          );
          final limitedRows = truncateSqlResultRows(
            normalized.data,
            options.maxRows,
          );
          return SqlCommandResult.success(
            index: result.index,
            rows: limitedRows,
            rowCount: limitedRows.length,
            affectedRows: normalized.affectedRows,
            columnMetadata: normalized.columnMetadata,
          );
        })
        .toList(growable: false);
  }

  QueryRequest queryRequestForCommand(
    SqlCommand command, {
    required String agentId,
    required String requestId,
  }) {
    return QueryRequest(
      id: requestId,
      agentId: agentId,
      query: command.sql,
      parameters: command.params,
      timestamp: DateTime.now(),
    );
  }
}
