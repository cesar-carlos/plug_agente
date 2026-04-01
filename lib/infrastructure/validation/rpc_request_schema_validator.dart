import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/trace_context_validator.dart';
import 'package:result_dart/result_dart.dart';

/// Validates RPC request payloads against the published communication contract.
///
/// The implementation enforces the subset of JSON Schema used by the agent at
/// runtime so the published docs match the actual request gate.
class RpcRequestSchemaValidator {
  const RpcRequestSchemaValidator();

  Result<void> validateSingle(
    Map<String, dynamic> data, {
    TransportLimits limits = const TransportLimits(),
  }) {
    final jsonrpc = data['jsonrpc'];
    if (jsonrpc != '2.0') {
      return _invalidRequest('Field "jsonrpc" must be exactly "2.0"');
    }

    final method = data['method'];
    if (method == null) {
      return _invalidRequest('Field "method" is required');
    }
    if (method is! String || method.trim().isEmpty) {
      return _invalidRequest('Field "method" must be a non-empty string');
    }

    final id = data['id'];
    if (id != null && id is! String && id is! num) {
      return _invalidRequest('Field "id" must be string, number, or null');
    }

    final apiVersion = data['api_version'];
    if (apiVersion != null && apiVersion is! String) {
      return _invalidRequest('Field "api_version" must be a string');
    }

    final meta = data['meta'];
    if (meta != null) {
      if (meta is! Map<String, dynamic>) {
        return _invalidRequest('Field "meta" must be an object');
      }
      final metaValidation = _validateMeta(meta);
      if (metaValidation.isError()) {
        return metaValidation;
      }
    }

    return switch (method) {
      'sql.execute' => _validateSqlExecuteParams(
        data['params'],
        limits.maxRows,
      ),
      'sql.executeBatch' => _validateSqlExecuteBatchParams(
        data['params'],
        limits.maxBatchSize,
        limits.maxRows,
      ),
      'sql.cancel' => _validateSqlCancelParams(data['params']),
      'agent.getProfile' => _validateAgentGetProfileParams(data['params']),
      _ => const Success(unit),
    };
  }

  Result<void> validateBatch(
    List<dynamic> data, {
    TransportLimits limits = const TransportLimits(),
  }) {
    if (data.isEmpty) {
      return _invalidRequest('Batch request cannot be empty');
    }
    if (data.length > limits.maxBatchSize) {
      return _invalidRequest(
        'Batch request exceeds limit: ${data.length} > ${limits.maxBatchSize}',
      );
    }

    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      if (item is! Map<String, dynamic>) {
        return _invalidRequest(
          'Batch item at index $i must be an object, '
          'got ${item.runtimeType}',
        );
      }
      final result = validateSingle(item, limits: limits);
      if (result.isError()) {
        final failure = result.exceptionOrNull()! as domain.Failure;
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Batch item at index $i: ${failure.message}',
            context: failure.context,
          ),
        );
      }
    }
    return const Success(unit);
  }

  Result<void> _validateMeta(Map<String, dynamic> meta) {
    const knownFields = {
      'trace_id',
      'traceparent',
      'tracestate',
      'request_id',
      'agent_id',
      'timestamp',
    };
    final extraFields = meta.keys.where((key) => !knownFields.contains(key));
    if (extraFields.isNotEmpty) {
      return _invalidRequest(
        'Field "meta" contains unsupported properties: '
        '${extraFields.join(", ")}',
      );
    }

    for (final key in [
      'trace_id',
      'traceparent',
      'tracestate',
      'request_id',
      'agent_id',
      'timestamp',
    ]) {
      final value = meta[key];
      if (value != null && value is! String) {
        return _invalidRequest('Field "meta.$key" must be a string');
      }
    }

    final timestamp = meta['timestamp'] as String?;
    if (timestamp != null && DateTime.tryParse(timestamp) == null) {
      return _invalidRequest('Field "meta.timestamp" must be ISO-8601');
    }

    final traceParent = meta['traceparent'] as String?;
    if (traceParent != null &&
        !TraceContextValidator.isValidTraceParent(traceParent)) {
      return _invalidRequest('Field "meta.traceparent" must follow W3C format');
    }

    final traceState = meta['tracestate'] as String?;
    if (traceState != null &&
        !TraceContextValidator.isValidTraceState(traceState)) {
      return _invalidRequest(
        'Field "meta.tracestate" must follow W3C semantics',
      );
    }

    return const Success(unit);
  }

  Result<void> _validateSqlExecuteParams(
    dynamic params,
    int maxRowsLimit,
  ) {
    if (params == null) {
      return _invalidParams(
        'Field "params" is required for method sql.execute',
      );
    }
    if (params is! Map<String, dynamic>) {
      return _invalidParams('Field "params" must be an object');
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
      return _invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final sql = params['sql'];
    if (sql is! String || sql.trim().isEmpty) {
      return _invalidParams('Field "params.sql" must be a non-empty string');
    }

    final parameters = params['params'];
    if (parameters != null && parameters is! Map<String, dynamic>) {
      return _invalidParams('Field "params.params" must be an object');
    }

    final tokenValidation = _validateTokenAliases(params);
    if (tokenValidation.isError()) {
      return tokenValidation;
    }

    final idempotencyKey = params['idempotency_key'];
    if (idempotencyKey != null &&
        (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
      return _invalidParams(
        'Field "params.idempotency_key" must be a non-empty string',
      );
    }

    final options = params['options'];
    if (options != null) {
      final optionsValidation = _validateOptions(
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
        if (multiResult == true &&
            parameters is Map<String, dynamic> &&
            parameters.isNotEmpty) {
          return _invalidParams(
            'Field "params.options.multi_result" is not supported with '
            'named parameters',
          );
        }
      }
    }

    final database = params['database'];
    if (database != null && database is! String) {
      return _invalidParams('Field "params.database" must be a string');
    }

    return const Success(unit);
  }

  Result<void> _validateSqlExecuteBatchParams(
    dynamic params,
    int maxBatchSize,
    int maxRowsLimit,
  ) {
    if (params == null) {
      return _invalidParams(
        'Field "params" is required for method sql.executeBatch',
      );
    }
    if (params is! Map<String, dynamic>) {
      return _invalidParams('Field "params" must be an object');
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
      return _invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final commands = params['commands'];
    if (commands is! List<dynamic> || commands.isEmpty) {
      return _invalidParams(
        'Field "params.commands" must be a non-empty array',
      );
    }
    if (commands.length > maxBatchSize) {
      return _invalidParams(
        'Field "params.commands" exceeds limit: '
        '${commands.length} > $maxBatchSize',
      );
    }

    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      if (command is! Map<String, dynamic>) {
        return _invalidParams(
          'Field "params.commands[$i]" must be an object',
        );
      }
      const allowedCommandKeys = {'sql', 'params', 'execution_order'};
      final extraCommandKeys = command.keys.where(
        (key) => !allowedCommandKeys.contains(key),
      );
      if (extraCommandKeys.isNotEmpty) {
        return _invalidParams(
          'Field "params.commands[$i]" contains unsupported properties: '
          '${extraCommandKeys.join(", ")}',
        );
      }
      final sql = command['sql'];
      if (sql is! String || sql.trim().isEmpty) {
        return _invalidParams(
          'Field "params.commands[$i].sql" must be a non-empty string',
        );
      }
      final commandParams = command['params'];
      if (commandParams != null && commandParams is! Map<String, dynamic>) {
        return _invalidParams(
          'Field "params.commands[$i].params" must be an object',
        );
      }
      final executionOrder = command['execution_order'];
      if (executionOrder != null &&
          (executionOrder is! int || executionOrder < 0)) {
        return _invalidParams(
          'Field "params.commands[$i].execution_order" must be '
          'an integer >= 0',
        );
      }
    }

    final tokenValidation = _validateTokenAliases(params);
    if (tokenValidation.isError()) {
      return tokenValidation;
    }

    final idempotencyKey = params['idempotency_key'];
    if (idempotencyKey != null &&
        (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
      return _invalidParams(
        'Field "params.idempotency_key" must be a non-empty string',
      );
    }

    final options = params['options'];
    if (options != null) {
      final optionsValidation = _validateOptions(
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
      return _invalidParams('Field "params.database" must be a string');
    }

    return const Success(unit);
  }

  Result<void> _validateSqlCancelParams(dynamic params) {
    if (params == null) {
      return _invalidParams('Field "params" is required for method sql.cancel');
    }
    if (params is! Map<String, dynamic>) {
      return _invalidParams('Field "params" must be an object');
    }

    const allowedKeys = {'execution_id', 'request_id'};
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return _invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final executionId = params['execution_id'];
    final requestId = params['request_id'];
    if ((executionId == null ||
            executionId is! String ||
            executionId.isEmpty) &&
        (requestId == null || requestId is! String || requestId.isEmpty)) {
      return _invalidParams(
        'At least one of params.execution_id or params.request_id is required',
      );
    }

    if (executionId != null && executionId is! String) {
      return _invalidParams('Field "params.execution_id" must be a string');
    }
    if (requestId != null && requestId is! String) {
      return _invalidParams('Field "params.request_id" must be a string');
    }

    return const Success(unit);
  }

  Result<void> _validateAgentGetProfileParams(dynamic params) {
    if (params == null) {
      return const Success(unit);
    }
    if (params is! Map<String, dynamic>) {
      return _invalidParams(
        'Field "params" must be an object when present for method agent.getProfile',
      );
    }
    const allowedKeys = {'client_token', 'clientToken', 'auth'};
    final extraKeys = params.keys.where(
      (String key) => !allowedKeys.contains(key),
    );
    if (extraKeys.isNotEmpty) {
      return _invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }
    return _validateTokenAliases(params);
  }

  Result<void> _validateTokenAliases(Map<String, dynamic> params) {
    for (final key in ['client_token', 'clientToken', 'auth']) {
      final value = params[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        return _invalidParams('Field "params.$key" must be a non-empty string');
      }
    }
    return const Success(unit);
  }

  Result<void> _validateOptions(
    dynamic options, {
    required bool allowTransaction,
    required int maxRowsLimit,
    required bool allowPreserveSql,
  }) {
    if (options is! Map<String, dynamic>) {
      return _invalidParams('Field "params.options" must be an object');
    }

    final allowedKeys = allowTransaction
        ? const {
            'timeout_ms',
            'max_rows',
            'transaction',
            'page',
            'page_size',
            'cursor',
          }
        : <String>{
            'timeout_ms',
            'max_rows',
            'page',
            'page_size',
            'cursor',
            'execution_mode',
            'multi_result',
            if (allowPreserveSql) 'preserve_sql',
          };
    final extraKeys = options.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return _invalidParams(
        'Field "params.options" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final timeoutMs = options['timeout_ms'];
    if (timeoutMs != null && (timeoutMs is! int || timeoutMs < 1)) {
      return _invalidParams('Field "params.options.timeout_ms" must be >= 1');
    }

    final maxRows = options['max_rows'];
    if (maxRows != null && (maxRows is! int || maxRows < 1)) {
      return _invalidParams('Field "params.options.max_rows" must be >= 1');
    }

    final page = options['page'];
    if (page != null && (page is! int || page < 1)) {
      return _invalidParams('Field "params.options.page" must be >= 1');
    }

    final pageSize = options['page_size'];
    if (pageSize != null && (pageSize is! int || pageSize < 1)) {
      return _invalidParams('Field "params.options.page_size" must be >= 1');
    }
    if (pageSize != null && pageSize is int && pageSize > maxRowsLimit) {
      return _invalidParams(
        'Field "params.options.page_size" exceeds limit: '
        '$pageSize > $maxRowsLimit',
      );
    }
    if ((page == null) != (pageSize == null)) {
      return _invalidParams(
        'Fields "params.options.page" and "params.options.page_size" '
        'must be provided together',
      );
    }

    final cursor = options['cursor'];
    if (cursor != null && (cursor is! String || cursor.trim().isEmpty)) {
      return _invalidParams('Field "params.options.cursor" must be a string');
    }
    if (cursor != null && (page != null || pageSize != null)) {
      return _invalidParams(
        'Field "params.options.cursor" cannot be combined with '
        '"page" or "page_size"',
      );
    }

    final preserveSql = options['preserve_sql'];
    if (preserveSql != null && preserveSql is! bool) {
      return _invalidParams(
        'Field "params.options.preserve_sql" must be a boolean',
      );
    }

    final executionMode = options['execution_mode'];
    if (executionMode != null &&
        (executionMode is! String ||
            (executionMode != 'managed' && executionMode != 'preserve'))) {
      return _invalidParams(
        'Field "params.options.execution_mode" must be "managed" or "preserve"',
      );
    }
    if (preserveSql == true && executionMode == 'managed') {
      return _invalidParams(
        'Field "params.options.preserve_sql" cannot be true when '
        '"execution_mode" is "managed"',
      );
    }
    if (preserveSql == true &&
        (page != null || pageSize != null || cursor != null)) {
      return _invalidParams(
        'Field "params.options.preserve_sql" cannot be combined with '
        'pagination options',
      );
    }
    if (executionMode == 'preserve' &&
        (page != null || pageSize != null || cursor != null)) {
      return _invalidParams(
        'Field "params.options.execution_mode" cannot be combined with '
        'pagination options when set to "preserve"',
      );
    }

    final multiResult = options['multi_result'];
    if (multiResult != null && multiResult is! bool) {
      return _invalidParams(
        'Field "params.options.multi_result" must be a boolean',
      );
    }
    if (multiResult == true &&
        (page != null || pageSize != null || cursor != null)) {
      return _invalidParams(
        'Field "params.options.multi_result" cannot be combined with '
        'pagination options',
      );
    }

    final transaction = options['transaction'];
    if (transaction != null && transaction is! bool) {
      return _invalidParams(
        'Field "params.options.transaction" must be a boolean',
      );
    }

    return const Success(unit);
  }

  Result<void> _invalidRequest(String message) {
    return Failure(
      domain.ValidationFailure.withContext(
        message: message,
        context: {'rpc_error_code': RpcErrorCode.invalidRequest},
      ),
    );
  }

  Result<void> _invalidParams(String message) {
    return Failure(
      domain.ValidationFailure.withContext(
        message: message,
        context: {'rpc_error_code': RpcErrorCode.invalidParams},
      ),
    );
  }
}
