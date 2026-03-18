import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
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
    final effectiveTimeout = timeout;

    if (opts.transaction) {
      return _databaseGateway.executeBatch(
        agentId,
        commands,
        database: database,
        options: opts,
        timeout: effectiveTimeout,
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

    // If any validation failed and transaction mode, fail early
    if (validationResults.isNotEmpty && opts.transaction) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Batch validation failed in transaction mode',
          context: {
            'failedCommands': validationResults.keys.toList(),
            'operation': 'sql_validation',
          },
        ),
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

      // Execute command
      final command = commands[i];
      final request = queryRequestForCommand(
        command,
        agentId: agentId,
        requestId: _uuid.v4(),
      );
      final executeResult = switch ((effectiveTimeout, database)) {
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

      await executeResult.fold(
        (response) async {
          // Normalize response
          final normalized = await _normalizerService.normalize(response);

          results.add(
            SqlCommandResult.success(
              index: i,
              rows: normalized.data,
              rowCount: normalized.data.length,
              affectedRows: normalized.affectedRows,
              columnMetadata: normalized.columnMetadata,
            ),
          );
        },
        (failure) async {
          final domainFailure = failure as domain.Failure;
          results.add(
            SqlCommandResult.failure(
              index: i,
              error: domainFailure.message,
            ),
          );

          // In transaction mode, abort on first error
          if (opts.transaction) {
            return;
          }
        },
      );

      // In transaction mode, abort if we hit an error
      if (opts.transaction && !results.last.ok) {
        break;
      }
    }

    // In transaction mode, if any failed, return failure
    if (opts.transaction && results.any((r) => !r.ok)) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Transaction aborted due to command failure',
          context: {
            'failedIndex': results.indexWhere((r) => !r.ok),
            'totalCommands': commands.length,
            'completedCommands': results.length,
          },
        ),
      );
    }

    return Success(results);
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
