import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/trace_context_validator.dart';
import 'package:result_dart/result_dart.dart';

class RpcContractValidator {
  const RpcContractValidator();

  Result<void> validateAgentRegister(Map<String, dynamic> data) {
    final agentId = data['agentId'];
    if (agentId is! String || agentId.trim().isEmpty) {
      return _invalid('Field "agentId" must be a non-empty string');
    }

    final timestamp = data['timestamp'];
    if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
      return _invalid('Field "timestamp" must be ISO-8601');
    }

    final capabilities = data['capabilities'];
    if (capabilities is! Map<String, dynamic>) {
      return _invalid('Field "capabilities" must be an object');
    }

    return _validateCapabilities(capabilities);
  }

  Result<void> validateAgentCapabilitiesEnvelope(Map<String, dynamic> data) {
    final capabilities = data['capabilities'];
    if (capabilities is! Map<String, dynamic>) {
      return _invalid('Field "capabilities" must be an object');
    }
    return _validateCapabilities(capabilities);
  }

  Result<void> validateResponse(Map<String, dynamic> data) {
    if (data['jsonrpc'] != '2.0') {
      return _invalid('Field "jsonrpc" must be exactly "2.0"');
    }

    final hasResult = data.containsKey('result');
    final hasError = data.containsKey('error');
    if (hasResult == hasError) {
      return _invalid(
        'Response must contain exactly one of "result" or "error"',
      );
    }

    final id = data['id'];
    if (id != null && id is! String && id is! num) {
      return _invalid('Field "id" must be string, number, or null');
    }

    final apiVersion = data['api_version'];
    if (apiVersion != null && apiVersion is! String) {
      return _invalid('Field "api_version" must be a string');
    }

    final metaValidation = _validateMeta(data['meta']);
    if (metaValidation.isError()) {
      return metaValidation;
    }

    if (hasError) {
      final error = data['error'];
      if (error is! Map<String, dynamic>) {
        return _invalid('Field "error" must be an object');
      }
      final code = error['code'];
      final message = error['message'];
      if (code is! int || message is! String || message.trim().isEmpty) {
        return _invalid('Field "error" must contain integer code and message');
      }
      return const Success(unit);
    }

    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      return _invalid('Field "result" must be an object');
    }
    return _validateResult(result);
  }

  Result<void> validateBatchResponse(List<dynamic> data) {
    if (data.isEmpty) {
      return _invalid('Batch response cannot be empty');
    }

    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      if (item is! Map<String, dynamic>) {
        return _invalid('Batch response item at index $i must be an object');
      }
      final result = validateResponse(item);
      if (result.isError()) {
        final failure = result.exceptionOrNull()! as domain.Failure;
        return _invalid('Batch response item at index $i: ${failure.message}');
      }
    }

    return const Success(unit);
  }

  Result<void> validateStreamChunk(Map<String, dynamic> data) {
    if (!_isNonEmptyString(data['stream_id'])) {
      return _invalid('Field "stream_id" must be a non-empty string');
    }
    final requestId = data['request_id'];
    if (requestId != null && requestId is! String && requestId is! num) {
      return _invalid('Field "request_id" must be string, number, or null');
    }
    final chunkIndex = data['chunk_index'];
    if (chunkIndex is! int || chunkIndex < 0) {
      return _invalid('Field "chunk_index" must be >= 0');
    }
    final rows = data['rows'];
    if (rows is! List<dynamic>) {
      return _invalid('Field "rows" must be an array');
    }
    if (rows.any((row) => row is! Map<String, dynamic>)) {
      return _invalid('Field "rows" must contain objects only');
    }

    final totalChunks = data['total_chunks'];
    if (totalChunks != null && (totalChunks is! int || totalChunks < 1)) {
      return _invalid('Field "total_chunks" must be >= 1');
    }

    final columnMetadata = data['column_metadata'];
    if (columnMetadata != null &&
        (columnMetadata is! List<dynamic> ||
            columnMetadata.any((item) => item is! Map<String, dynamic>))) {
      return _invalid('Field "column_metadata" must be an array of objects');
    }

    return const Success(unit);
  }

  Result<void> validateStreamComplete(Map<String, dynamic> data) {
    if (!_isNonEmptyString(data['stream_id'])) {
      return _invalid('Field "stream_id" must be a non-empty string');
    }
    final requestId = data['request_id'];
    if (requestId != null && requestId is! String && requestId is! num) {
      return _invalid('Field "request_id" must be string, number, or null');
    }
    final totalRows = data['total_rows'];
    if (totalRows is! int || totalRows < 0) {
      return _invalid('Field "total_rows" must be >= 0');
    }

    for (final key in ['affected_rows']) {
      final value = data[key];
      if (value != null && (value is! int || value < 0)) {
        return _invalid('Field "$key" must be >= 0');
      }
    }

    for (final key in ['started_at', 'finished_at']) {
      final value = data[key];
      if (value != null &&
          (value is! String || DateTime.tryParse(value) == null)) {
        return _invalid('Field "$key" must be ISO-8601 when provided');
      }
    }

    final executionId = data['execution_id'];
    if (executionId != null && !_isNonEmptyString(executionId)) {
      return _invalid('Field "execution_id" must be a non-empty string');
    }

    return const Success(unit);
  }

  Result<void> _validateCapabilities(Map<String, dynamic> data) {
    try {
      final capabilities = ProtocolCapabilities.fromJson(data);
      if (capabilities.protocols.isEmpty ||
          capabilities.encodings.isEmpty ||
          capabilities.compressions.isEmpty) {
        return _invalid(
          'Capabilities must declare protocols, encodings, and compressions',
        );
      }
      return const Success(unit);
    } on Object {
      return _invalid('Capabilities payload is malformed');
    }
  }

  Result<void> _validateResult(Map<String, dynamic> result) {
    for (final key in [
      'execution_id',
      'stream_id',
      'started_at',
      'finished_at',
      'current_cursor',
      'next_cursor',
    ]) {
      final value = result[key];
      if (value != null && value is! String) {
        return _invalid('Field "$key" must be a string');
      }
    }

    for (final key in ['row_count', 'returned_rows', 'affected_rows']) {
      final value = result[key];
      if (value != null && (value is! int || value < 0)) {
        return _invalid('Field "$key" must be >= 0');
      }
    }

    final multiResult = result['multi_result'];
    if (multiResult != null && multiResult is! bool) {
      return _invalid('Field "multi_result" must be a boolean');
    }
    for (final key in ['result_set_count', 'item_count']) {
      final value = result[key];
      if (value != null && (value is! int || value < 0)) {
        return _invalid('Field "$key" must be >= 0');
      }
    }

    final rows = result['rows'];
    if (rows != null &&
        (rows is! List<dynamic> ||
            rows.any((row) => row is! Map<String, dynamic>))) {
      return _invalid('Field "rows" must be an array of objects');
    }

    final columnMetadata = result['column_metadata'];
    if (columnMetadata != null &&
        (columnMetadata is! List<dynamic> ||
            columnMetadata.any((item) => item is! Map<String, dynamic>))) {
      return _invalid('Field "column_metadata" must be an array of objects');
    }

    final truncated = result['truncated'];
    if (truncated != null && truncated is! bool) {
      return _invalid('Field "truncated" must be a boolean');
    }

    for (final key in ['started_at', 'finished_at']) {
      final value = result[key];
      if (value != null &&
          (value is! String || DateTime.tryParse(value) == null)) {
        return _invalid('Field "$key" must be ISO-8601 when provided');
      }
    }

    final pagination = result['pagination'];
    if (pagination != null) {
      if (pagination is! Map<String, dynamic>) {
        return _invalid('Field "pagination" must be an object');
      }
      for (final key in ['page', 'page_size', 'returned_rows']) {
        final value = pagination[key];
        final min = key == 'returned_rows' ? 0 : 1;
        if (value is! int || value < min) {
          return _invalid(
            'Field "pagination.$key" must be an integer >= $min',
          );
        }
      }
      for (final key in ['has_next_page', 'has_previous_page']) {
        if (pagination[key] is! bool) {
          return _invalid('Field "pagination.$key" must be a boolean');
        }
      }
      for (final key in ['current_cursor', 'next_cursor']) {
        final value = pagination[key];
        if (value != null && value is! String) {
          return _invalid('Field "pagination.$key" must be a string');
        }
      }
    }

    final resultSets = result['result_sets'];
    if (resultSets != null) {
      if (resultSets is! List<dynamic>) {
        return _invalid('Field "result_sets" must be an array');
      }
      for (final item in resultSets) {
        final validation = _validateResultSetItem(item);
        if (validation.isError()) {
          return validation;
        }
      }
    }

    final items = result['items'];
    if (items != null) {
      if (items is! List<dynamic>) {
        return _invalid('Field "items" must be an array');
      }
      if (items.isEmpty) {
        return const Success(unit);
      }
      final first = items.first;
      final isBatchShape =
          first is Map<String, dynamic> && first.containsKey('ok');
      for (final item in items) {
        final validation = isBatchShape
            ? _validateBatchCommandResultItem(item)
            : _validateResponseItem(item);
        if (validation.isError()) {
          return validation;
        }
      }
    }

    return const Success(unit);
  }

  Result<void> _validateBatchCommandResultItem(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return _invalid('Field "items" must contain objects');
    }

    final index = item['index'];
    if (index is! int || index < 0) {
      return _invalid('Field "items[].index" must be an integer >= 0');
    }

    final ok = item['ok'];
    if (ok is! bool) {
      return _invalid('Field "items[].ok" must be a boolean');
    }

    if (!ok) {
      final err = item['error'];
      if (err != null && err is! String) {
        return _invalid('Field "items[].error" must be a string');
      }
      return const Success(unit);
    }

    final rows = item['rows'];
    if (rows != null &&
        (rows is! List<dynamic> ||
            rows.any((row) => row is! Map<String, dynamic>))) {
      return _invalid('Field "items[].rows" must be an array of objects');
    }

    for (final key in ['row_count', 'affected_rows']) {
      final value = item[key];
      if (value != null && (value is! int || value < 0)) {
        return _invalid('Field "items[].$key" must be an integer >= 0');
      }
    }

    final columnMetadata = item['column_metadata'];
    if (columnMetadata != null &&
        (columnMetadata is! List<dynamic> ||
            columnMetadata.any((entry) => entry is! Map<String, dynamic>))) {
      return _invalid(
        'Field "items[].column_metadata" must be an array of objects',
      );
    }

    return const Success(unit);
  }

  Result<void> _validateResultSetItem(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return _invalid('Field "result_sets" must contain objects');
    }

    final index = item['index'];
    if (index is! int || index < 0) {
      return _invalid('Field "result_sets[].index" must be >= 0');
    }

    final rows = item['rows'];
    if (rows is! List<dynamic> ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      return _invalid('Field "result_sets[].rows" must be an array of objects');
    }

    for (final key in ['row_count', 'affected_rows']) {
      final value = item[key];
      if (value != null && (value is! int || value < 0)) {
        return _invalid('Field "result_sets[].$key" must be >= 0');
      }
    }

    final columnMetadata = item['column_metadata'];
    if (columnMetadata != null &&
        (columnMetadata is! List<dynamic> ||
            columnMetadata.any((entry) => entry is! Map<String, dynamic>))) {
      return _invalid(
        'Field "result_sets[].column_metadata" must be an array of objects',
      );
    }

    return const Success(unit);
  }

  Result<void> _validateResponseItem(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return _invalid('Field "items" must contain objects');
    }

    final type = item['type'];
    if (type != 'result_set' && type != 'row_count') {
      return _invalid('Field "items[].type" must be result_set or row_count');
    }

    final index = item['index'];
    if (index is! int || index < 0) {
      return _invalid('Field "items[].index" must be >= 0');
    }

    if (type == 'row_count') {
      final affectedRows = item['affected_rows'];
      if (affectedRows != null && (affectedRows is! int || affectedRows < 0)) {
        return _invalid('Field "items[].affected_rows" must be >= 0');
      }
      return const Success(unit);
    }

    final resultSetIndex = item['result_set_index'];
    if (resultSetIndex != null &&
        (resultSetIndex is! int || resultSetIndex < 0)) {
      return _invalid('Field "items[].result_set_index" must be >= 0');
    }

    return _validateResultSetItem(item);
  }

  Result<void> _validateMeta(dynamic meta) {
    if (meta == null) {
      return const Success(unit);
    }
    if (meta is! Map<String, dynamic>) {
      return _invalid('Field "meta" must be an object');
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
        return _invalid('Field "meta.$key" must be a string');
      }
    }

    final timestamp = meta['timestamp'] as String?;
    if (timestamp != null && DateTime.tryParse(timestamp) == null) {
      return _invalid('Field "meta.timestamp" must be ISO-8601');
    }

    final traceparent = meta['traceparent'] as String?;
    if (traceparent != null &&
        !TraceContextValidator.isValidTraceParent(traceparent)) {
      return _invalid('Field "meta.traceparent" must follow W3C format');
    }

    final tracestate = meta['tracestate'] as String?;
    if (tracestate != null &&
        !TraceContextValidator.isValidTraceState(tracestate)) {
      return _invalid('Field "meta.tracestate" must follow W3C semantics');
    }

    return const Success(unit);
  }

  bool _isNonEmptyString(dynamic value) {
    return value is String && value.trim().isNotEmpty;
  }

  Result<void> _invalid(String message) {
    return Failure(
      domain.ValidationFailure.withContext(
        message: message,
        context: {'rpc_error_code': RpcErrorCode.internalError},
      ),
    );
  }
}
