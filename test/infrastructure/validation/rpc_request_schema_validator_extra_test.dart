import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

void main() {
  group('RpcRequestSchemaValidator extra coverage', () {
    const validator = RpcRequestSchemaValidator();

    test('should reject meta with unsupported property', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': '1',
        'params': {'sql': 'SELECT 1'},
        'meta': <String, dynamic>{
          'unknown_field': 'x',
        },
      };

      final result = validator.validateSingle(data);
      check(result.isError()).isTrue();
      final err = result.exceptionOrNull()! as domain.ValidationFailure;
      check(err.message).contains('unsupported');
      check(err.context['rpc_error_code']).equals(RpcErrorCode.invalidRequest);
    });

    test('should reject meta.timestamp that is not ISO-8601', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': '1',
        'params': {'sql': 'SELECT 1'},
        'meta': <String, dynamic>{
          'timestamp': 'yesterday',
        },
      };

      final result = validator.validateSingle(data);
      check(result.isError()).isTrue();
    });

    test('validateBatch should reject empty list', () {
      final result = validator.validateBatch(<dynamic>[]);
      check(result.isError()).isTrue();
      final err = result.exceptionOrNull()! as domain.ValidationFailure;
      check(err.context['rpc_error_code']).equals(RpcErrorCode.invalidRequest);
    });

    test('should reject params.options when not an object', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': '1',
        'params': {
          'sql': 'SELECT 1',
          'options': true,
        },
      };

      final result = validator.validateSingle(data);
      check(result.isError()).isTrue();
      final err = result.exceptionOrNull()! as domain.ValidationFailure;
      check(err.context['rpc_error_code']).equals(RpcErrorCode.invalidParams);
    });

    test('should reject empty client_token string', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': '1',
        'params': {
          'sql': 'SELECT 1',
          'client_token': '   ',
        },
      };

      final result = validator.validateSingle(data);
      check(result.isError()).isTrue();
    });

    test('should reject whitespace-only idempotency_key', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': '1',
        'params': {
          'sql': 'SELECT 1',
          'idempotency_key': '  ',
        },
      };

      final result = validator.validateSingle(data);
      check(result.isError()).isTrue();
    });

    test('should accept sql.cancel with only execution_id', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.cancel',
        'id': '1',
        'params': <String, dynamic>{
          'execution_id': 'exec-1',
        },
      };

      final result = validator.validateSingle(data);
      check(result.isSuccess()).isTrue();
    });

    test('should accept sql.executeBatch with transaction option', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.executeBatch',
        'id': '1',
        'params': {
          'commands': [
            {'sql': 'SELECT 1'},
          ],
          'options': {'transaction': true},
        },
      };

      final result = validator.validateSingle(data);
      check(result.isSuccess()).isTrue();
    });

    test('should reject preserve_sql combined with pagination', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': '1',
        'params': {
          'sql': 'SELECT 1',
          'options': {
            'preserve_sql': true,
            'page': 1,
            'page_size': 10,
          },
        },
      };

      final result = validator.validateSingle(
        data,
        limits: const TransportLimits(maxRows: 100),
      );
      check(result.isError()).isTrue();
    });

    test('should succeed for unknown method without params validation', () {
      final data = <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'rpc.notRegisteredInValidator',
        'id': '1',
      };

      final result = validator.validateSingle(data);
      check(result.isSuccess()).isTrue();
    });
  });
}
