import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validation_support.dart';
import 'package:result_dart/result_dart.dart';

/// SQL RPC method parameter validators.
final class RpcRequestSchemaSqlParamsValidator {
  const RpcRequestSchemaSqlParamsValidator();

  Result<void> validateSqlExecuteParams(
    dynamic params,
    int maxRowsLimit,
  ) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" is required for method sql.execute',
      );
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params" must be an object');
    }

    final allowedKeys = {
      'sql',
      'params',
      'client_token',
      'clientToken',
      'auth',
      'idempotency_key',
      'options',
      'database',
    };
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final sql = params['sql'];
    if (sql is! String || sql.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.sql" must be a non-empty string');
    }

    final parameters = params['params'];
    if (parameters != null && parameters is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.params" must be an object');
    }

    final tokenValidation = RpcRequestSchemaValidationSupport.validateTokenAliases(params);
    if (tokenValidation.isError()) {
      return tokenValidation;
    }

    final idempotencyKey = params['idempotency_key'];
    if (idempotencyKey != null && (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.idempotency_key" must be a non-empty string',
      );
    }

    final options = params['options'];
    if (options != null) {
      final optionsValidation = RpcRequestSchemaValidationSupport.validateOptions(
        options,
        allowTransaction: false,
        maxRowsLimit: maxRowsLimit,
        allowPreserveSql: true,
      );
      if (optionsValidation.isError()) {
        return optionsValidation;
      }

      if (options is Map<String, dynamic>) {
        final multiResult = options['multi_result'];
        if (multiResult == true && parameters is Map<String, dynamic> && parameters.isNotEmpty) {
          return RpcRequestSchemaValidationSupport.invalidParams(
            'Field "params.options.multi_result" is not supported with '
            'named parameters',
          );
        }
      }
    }

    final database = params['database'];
    if (database != null && database is! String) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.database" must be a string');
    }

    return const Success(unit);
  }

  Result<void> validateSqlExecuteBatchParams(
    dynamic params,
    int maxBatchSize,
    int maxRowsLimit,
  ) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" is required for method sql.executeBatch',
      );
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params" must be an object');
    }

    final allowedKeys = {
      'commands',
      'client_token',
      'clientToken',
      'auth',
      'idempotency_key',
      'options',
      'database',
    };
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final commands = params['commands'];
    if (commands is! List<dynamic> || commands.isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.commands" must be a non-empty array',
      );
    }
    if (commands.length > maxBatchSize) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.commands" exceeds limit: '
        '${commands.length} > $maxBatchSize',
      );
    }

    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      if (command is! Map<String, dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.commands[$i]" must be an object',
        );
      }
      const allowedCommandKeys = {'sql', 'params', 'execution_order'};
      final extraCommandKeys = command.keys.where(
        (key) => !allowedCommandKeys.contains(key),
      );
      if (extraCommandKeys.isNotEmpty) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.commands[$i]" contains unsupported properties: '
          '${extraCommandKeys.join(", ")}',
        );
      }
      final sql = command['sql'];
      if (sql is! String || sql.trim().isEmpty) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.commands[$i].sql" must be a non-empty string',
        );
      }
      final commandParams = command['params'];
      if (commandParams != null && commandParams is! Map<String, dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.commands[$i].params" must be an object',
        );
      }
      final executionOrder = command['execution_order'];
      if (executionOrder != null && (executionOrder is! int || executionOrder < 0)) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.commands[$i].execution_order" must be '
          'an integer >= 0',
        );
      }
    }

    final tokenValidation = RpcRequestSchemaValidationSupport.validateTokenAliases(params);
    if (tokenValidation.isError()) {
      return tokenValidation;
    }

    final idempotencyKey = params['idempotency_key'];
    if (idempotencyKey != null && (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.idempotency_key" must be a non-empty string',
      );
    }

    final options = params['options'];
    if (options != null) {
      final optionsValidation = RpcRequestSchemaValidationSupport.validateOptions(
        options,
        allowTransaction: true,
        maxRowsLimit: maxRowsLimit,
        allowPreserveSql: false,
      );
      if (optionsValidation.isError()) {
        return optionsValidation;
      }
    }

    final database = params['database'];
    if (database != null && database is! String) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.database" must be a string');
    }

    return const Success(unit);
  }

  Result<void> validateSqlBulkInsertParams(
    dynamic params,
    int maxRowsLimit,
  ) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" is required for method sql.bulkInsert',
      );
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params" must be an object');
    }

    const allowedKeys = {
      'table',
      'columns',
      'rows',
      'client_token',
      'clientToken',
      'auth',
      'idempotency_key',
      'options',
      'database',
    };
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final table = params['table'];
    if (table is! String || table.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.table" must be a non-empty string');
    }

    final columns = params['columns'];
    if (columns is! List<dynamic> || columns.isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.columns" must be a non-empty array',
      );
    }
    const allowedColumnTypes = {
      'i32',
      'i64',
      'text',
      'decimal',
      'binary',
      'timestamp',
    };
    for (var i = 0; i < columns.length; i++) {
      final column = columns[i];
      if (column is! Map<String, dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.columns[$i]" must be an object',
        );
      }
      const allowedColumnKeys = {'name', 'type', 'nullable', 'max_len', 'maxLen'};
      final extraColumnKeys = column.keys.where((key) => !allowedColumnKeys.contains(key));
      if (extraColumnKeys.isNotEmpty) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.columns[$i]" contains unsupported properties: '
          '${extraColumnKeys.join(", ")}',
        );
      }
      final name = column['name'];
      if (name is! String || name.trim().isEmpty) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.columns[$i].name" must be a non-empty string',
        );
      }
      final type = column['type'];
      if (type is! String || !allowedColumnTypes.contains(type)) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.columns[$i].type" must be one of ${allowedColumnTypes.join(", ")}',
        );
      }
      final nullable = column['nullable'];
      if (nullable != null && nullable is! bool) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.columns[$i].nullable" must be a boolean',
        );
      }
      final maxLen = column['max_len'] ?? column['maxLen'];
      if (maxLen != null && (maxLen is! int || maxLen < 0)) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.columns[$i].max_len" must be an integer >= 0',
        );
      }
    }

    final rows = params['rows'];
    if (rows is! List<dynamic> || rows.isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.rows" must be a non-empty array');
    }
    if (rows.length > maxRowsLimit) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.rows" exceeds limit: ${rows.length} > $maxRowsLimit',
      );
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! List<dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidParams('Field "params.rows[$i]" must be an array');
      }
      if (row.length != columns.length) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.rows[$i]" length must match columns length',
        );
      }
    }

    final tokenValidation = RpcRequestSchemaValidationSupport.validateTokenAliases(params);
    if (tokenValidation.isError()) {
      return tokenValidation;
    }

    final idempotencyKey = params['idempotency_key'];
    if (idempotencyKey != null && (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.idempotency_key" must be a non-empty string',
      );
    }

    final options = params['options'];
    if (options != null) {
      if (options is! Map<String, dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidParams('Field "params.options" must be an object');
      }
      const allowedOptions = {'timeout_ms'};
      final extraOptionKeys = options.keys.where((key) => !allowedOptions.contains(key));
      if (extraOptionKeys.isNotEmpty) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.options" contains unsupported properties: '
          '${extraOptionKeys.join(", ")}',
        );
      }
      final timeout = options['timeout_ms'];
      if (timeout != null && (timeout is! int || timeout < 1)) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.options.timeout_ms" must be an integer >= 1',
        );
      }
    }

    final database = params['database'];
    if (database != null && database is! String) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.database" must be a string');
    }

    return const Success(unit);
  }

  Result<void> validateSqlCancelParams(dynamic params) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params" is required for method sql.cancel');
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params" must be an object');
    }

    const allowedKeys = {'execution_id', 'request_id'};
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final executionId = params['execution_id'];
    final requestId = params['request_id'];
    if ((executionId == null || executionId is! String || executionId.isEmpty) &&
        (requestId == null || requestId is! String || requestId.isEmpty)) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'At least one of params.execution_id or params.request_id is required',
      );
    }

    if (executionId != null && executionId is! String) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.execution_id" must be a string');
    }
    if (requestId != null && requestId is! String) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.request_id" must be a string');
    }

    return const Success(unit);
  }
}
