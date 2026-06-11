import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/trace_context_validator.dart';
import 'package:result_dart/result_dart.dart';

/// Shared validation helpers used by RPC request schema validators.
final class RpcRequestSchemaValidationSupport {
  RpcRequestSchemaValidationSupport._();

  static Result<void> invalidRequest(String message) {
    return Failure(
      domain.ValidationFailure.withContext(
        message: message,
        context: {'rpc_error_code': RpcErrorCode.invalidRequest},
      ),
    );
  }

  static Result<void> invalidParams(String message) {
    return Failure(
      domain.ValidationFailure.withContext(
        message: message,
        context: {'rpc_error_code': RpcErrorCode.invalidParams},
      ),
    );
  }

  static Result<void> validateMeta(Map<String, dynamic> meta) {
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
      return invalidRequest(
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
        return invalidRequest('Field "meta.$key" must be a string');
      }
    }

    final timestamp = meta['timestamp'] as String?;
    if (timestamp != null && DateTime.tryParse(timestamp) == null) {
      return invalidRequest('Field "meta.timestamp" must be ISO-8601');
    }

    final traceParent = meta['traceparent'] as String?;
    if (traceParent != null && !TraceContextValidator.isValidTraceParent(traceParent)) {
      return invalidRequest('Field "meta.traceparent" must follow W3C format');
    }

    final traceState = meta['tracestate'] as String?;
    if (traceState != null && !TraceContextValidator.isValidTraceState(traceState)) {
      return invalidRequest(
        'Field "meta.tracestate" must follow W3C semantics',
      );
    }

    return const Success(unit);
  }

  static Result<void> validateTokenAliases(Map<String, dynamic> params) {
    for (final key in ['client_token', 'clientToken', 'auth']) {
      final value = params[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        return invalidParams('Field "params.$key" must be a non-empty string');
      }
    }
    return const Success(unit);
  }

  static int? tryParseNonNegativeInt(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw < 0 ? null : raw;
    }
    if (raw is double) {
      if (raw.isNaN || raw.isInfinite) {
        return null;
      }
      final rounded = raw.round();
      if ((raw - rounded).abs() > 1e-9) {
        return null;
      }
      return rounded < 0 ? null : rounded;
    }
    return null;
  }

  static int? tryParsePositiveInt(Object? raw) {
    final parsed = tryParseNonNegativeInt(raw);
    if (parsed == null || parsed < 1) {
      return null;
    }
    return parsed;
  }

  static Result<void> validateOptions(
    dynamic options, {
    required bool allowTransaction,
    required int maxRowsLimit,
    required bool allowPreserveSql,
  }) {
    if (options is! Map<String, dynamic>) {
      return invalidParams('Field "params.options" must be an object');
    }

    final allowedKeys = allowTransaction
        ? const {
            'timeout_ms',
            'max_rows',
            'transaction',
            'max_parallel_read_only_batch_items',
          }
        : <String>{
            'timeout_ms',
            'max_rows',
            'page',
            'page_size',
            'cursor',
            'execution_mode',
            'multi_result',
            'prefer_db_streaming',
            if (allowPreserveSql) 'preserve_sql',
          };
    final extraKeys = options.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return invalidParams(
        'Field "params.options" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }

    final timeoutMs = options['timeout_ms'];
    if (timeoutMs != null && (timeoutMs is! int || timeoutMs < 1)) {
      return invalidParams('Field "params.options.timeout_ms" must be >= 1');
    }

    final maxRows = options['max_rows'];
    if (maxRows != null && (maxRows is! int || maxRows < 1)) {
      return invalidParams('Field "params.options.max_rows" must be >= 1');
    }

    final maxParallelReadOnlyBatchItems = options['max_parallel_read_only_batch_items'];
    if (maxParallelReadOnlyBatchItems != null &&
        (maxParallelReadOnlyBatchItems is! int || maxParallelReadOnlyBatchItems < 1)) {
      return invalidParams(
        'Field "params.options.max_parallel_read_only_batch_items" must be >= 1',
      );
    }

    final page = options['page'];
    if (page != null && (page is! int || page < 1)) {
      return invalidParams('Field "params.options.page" must be >= 1');
    }

    final pageSize = options['page_size'];
    if (pageSize != null && (pageSize is! int || pageSize < 1)) {
      return invalidParams('Field "params.options.page_size" must be >= 1');
    }
    if (pageSize != null && pageSize is int && pageSize > maxRowsLimit) {
      return invalidParams(
        'Field "params.options.page_size" exceeds limit: '
        '$pageSize > $maxRowsLimit',
      );
    }
    if ((page == null) != (pageSize == null)) {
      return invalidParams(
        'Fields "params.options.page" and "params.options.page_size" '
        'must be provided together',
      );
    }

    final cursor = options['cursor'];
    if (cursor != null && (cursor is! String || cursor.trim().isEmpty)) {
      return invalidParams('Field "params.options.cursor" must be a string');
    }
    if (cursor != null && (page != null || pageSize != null)) {
      return invalidParams(
        'Field "params.options.cursor" cannot be combined with '
        '"page" or "page_size"',
      );
    }

    final preserveSql = options['preserve_sql'];
    if (preserveSql != null && preserveSql is! bool) {
      return invalidParams(
        'Field "params.options.preserve_sql" must be a boolean',
      );
    }

    final executionMode = options['execution_mode'];
    if (executionMode != null &&
        (executionMode is! String || (executionMode != 'managed' && executionMode != 'preserve'))) {
      return invalidParams(
        'Field "params.options.execution_mode" must be "managed" or "preserve"',
      );
    }
    if (preserveSql == true && executionMode == 'managed') {
      return invalidParams(
        'Field "params.options.preserve_sql" cannot be true when '
        '"execution_mode" is "managed"',
      );
    }
    if (preserveSql == true && (page != null || pageSize != null || cursor != null)) {
      return invalidParams(
        'Field "params.options.preserve_sql" cannot be combined with '
        'pagination options',
      );
    }
    if (executionMode == 'preserve' && (page != null || pageSize != null || cursor != null)) {
      return invalidParams(
        'Field "params.options.execution_mode" cannot be combined with '
        'pagination options when set to "preserve"',
      );
    }

    final multiResult = options['multi_result'];
    if (multiResult != null && multiResult is! bool) {
      return invalidParams(
        'Field "params.options.multi_result" must be a boolean',
      );
    }

    final preferDbStreaming = options['prefer_db_streaming'];
    if (preferDbStreaming != null && preferDbStreaming is! bool) {
      return invalidParams(
        'Field "params.options.prefer_db_streaming" must be a boolean',
      );
    }
    if (multiResult == true && (page != null || pageSize != null || cursor != null)) {
      return invalidParams(
        'Field "params.options.multi_result" cannot be combined with '
        'pagination options',
      );
    }

    final transaction = options['transaction'];
    if (transaction != null && transaction is! bool) {
      return invalidParams(
        'Field "params.options.transaction" must be a boolean',
      );
    }

    return const Success(unit);
  }
}
