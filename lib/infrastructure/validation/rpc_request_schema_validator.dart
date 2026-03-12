import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Validates RPC request payload against JSON-RPC 2.0 + v2.1 schema rules.
///
/// When `enableSocketSchemaValidation` is active, use before parsing to
/// reject malformed requests with standardized errors.
class RpcRequestSchemaValidator {
  const RpcRequestSchemaValidator();

  /// Validates [data] as a single RPC request. Returns [Success] if valid,
  /// [Failure] with technical message if invalid.
  Result<void> validateSingle(Map<String, dynamic> data) {
    final jsonrpc = data['jsonrpc'];
    if (jsonrpc != '2.0') {
      return Failure(
        domain.ValidationFailure(
          _message('jsonrpc', jsonrpc, 'must be exactly "2.0"'),
        ),
      );
    }

    final method = data['method'];
    if (method == null) {
      return Failure(
        domain.ValidationFailure(_message('method', null, 'is required')),
      );
    }
    if (method is! String) {
      return Failure(
        domain.ValidationFailure(
          _message('method', method, 'must be a string'),
        ),
      );
    }
    if (method.isEmpty) {
      return Failure(
        domain.ValidationFailure(
          _message('method', method, 'must not be empty'),
        ),
      );
    }

    final id = data['id'];
    if (id != null && id is! String && id is! num) {
      return Failure(
        domain.ValidationFailure(
          _message('id', id, 'must be string, number, or null'),
        ),
      );
    }

    final meta = data['meta'];
    if (meta != null && meta is! Map) {
      return Failure(
        domain.ValidationFailure(_message('meta', meta, 'must be an object')),
      );
    }

    return const Success(unit);
  }

  /// Validates [data] as a batch request (list of RPC requests).
  /// Returns [Success] if all items are valid objects, [Failure] with
  /// first error found.
  Result<void> validateBatch(List<dynamic> data) {
    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      if (item is! Map<String, dynamic>) {
        return Failure(
          domain.ValidationFailure(
            'Batch item at index $i must be an object, got ${item.runtimeType}',
          ),
        );
      }
      final result = validateSingle(item);
      if (result.isError()) {
        final failure = result.exceptionOrNull()! as domain.Failure;
        return Failure(
          domain.ValidationFailure(
            'Batch item at index $i: ${failure.message}',
          ),
        );
      }
    }
    return const Success(unit);
  }

  String _message(String field, Object? value, String requirement) {
    return 'Field "$field" $requirement (got: $value)';
  }
}
