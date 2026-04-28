import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

void main() {
  group('RpcRequestSchemaValidator', () {
    const validator = RpcRequestSchemaValidator();

    group('validateSingle', () {
      test('should succeed for valid request', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {'sql': 'SELECT 1'},
        };

        final result = validator.validateSingle(data);

        check(result.isSuccess()).isTrue();
      });

      test('should succeed for notification (null id)', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': null,
          'params': {'sql': 'SELECT 1'},
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when jsonrpc is not 2.0', () {
        final data = <String, dynamic>{
          'jsonrpc': '1.0',
          'method': 'sql.execute',
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('2.0'));
      });

      test('should fail when method is missing', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('method'));
      });

      test('should fail when method is not string', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 123,
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('string'));
      });

      test('should fail when method is empty', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': '',
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('empty'));
      });

      test('should fail when id is invalid type', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': <String>['invalid'],
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('id'));
      });

      test('should fail when traceparent is malformed', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {'sql': 'SELECT 1'},
          'meta': {
            'traceparent': 'invalid-traceparent',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test('should fail when tracestate is malformed', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {'sql': 'SELECT 1'},
          'meta': {
            'tracestate': 'invalid tracestate without separator',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test(
        'should fail with invalidParams for sql.execute schema violations',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': '',
              'unexpected': true,
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
          final err = result.exceptionOrNull()! as domain.ValidationFailure;
          expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
        },
      );

      test(
        'should fail when sql.executeBatch exceeds negotiated batch size',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.executeBatch',
            'id': 'req-1',
            'params': {
              'commands': List.generate(
                3,
                (index) => {'sql': 'SELECT $index'},
              ),
            },
          };

          final result = validator.validateSingle(
            data,
            limits: const TransportLimits(maxBatchSize: 2),
          );

          expect(result.isError(), isTrue);
          final err = result.exceptionOrNull()! as domain.ValidationFailure;
          expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
        },
      );

      test('should succeed for sql.executeBatch with execution_order', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.executeBatch',
          'id': 'req-1',
          'params': {
            'commands': [
              {'sql': 'SELECT 1', 'execution_order': 2},
              {'sql': 'SELECT 2', 'execution_order': 1},
              {'sql': 'SELECT 3'},
            ],
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when sql.executeBatch execution_order is invalid', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.executeBatch',
          'id': 'req-1',
          'params': {
            'commands': [
              {'sql': 'SELECT 1', 'execution_order': -1},
            ],
          },
        };

        final result = validator.validateSingle(data);

        check(result.isError()).isTrue();
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        check(err.context['rpc_error_code']).equals(RpcErrorCode.invalidParams);
        check(err.message).contains('execution_order');
      });

      test('should fail when sql.cancel omits execution identifiers', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.cancel',
          'id': 'req-1',
          'params': <String, dynamic>{},
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.getProfile params with client token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getProfile',
          'id': 'req-1',
          'params': {
            'client_token': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject unsupported agent.getProfile params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getProfile',
          'id': 'req-1',
          'params': {
            'unexpected': true,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.getHealth params with client token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getHealth',
          'id': 'req-1',
          'params': {
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject unsupported agent.getHealth params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getHealth',
          'id': 'req-1',
          'params': {
            'extra': 1,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept client_token.getPolicy params with client token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'client_token.getPolicy',
          'id': 'req-1',
          'params': {
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject unsupported client_token.getPolicy params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'client_token.getPolicy',
          'id': 'req-1',
          'params': {
            'extra': 1,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should succeed when id is number', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 1,
          'params': {'sql': 'SELECT 1'},
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute pagination options', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {'page': 2, 'page_size': 100},
          },
        };

        final result = validator.validateSingle(
          data,
          limits: const TransportLimits(maxRows: 200),
        );

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when page_size exceeds negotiated max_rows', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {'page': 1, 'page_size': 500},
          },
        };

        final result = validator.validateSingle(
          data,
          limits: const TransportLimits(maxRows: 100),
        );

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should succeed for sql.execute cursor pagination option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {'cursor': 'opaque-token'},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute multi_result option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1; SELECT 2;',
            'options': {'multi_result': true},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute execution_mode preserve option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT * FROM users LIMIT 10',
            'options': {'execution_mode': 'preserve'},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for deprecated preserve_sql alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT * FROM users LIMIT 10',
            'options': {'preserve_sql': true},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test(
        'should fail when multi_result is combined with pagination options',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT 1; SELECT 2;',
              'options': {
                'multi_result': true,
                'page': 1,
                'page_size': 100,
              },
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );

      test(
        'should fail when multi_result is combined with named parameters',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT * FROM users WHERE id = :id; SELECT 2;',
              'params': {'id': 1},
              'options': {'multi_result': true},
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );

      test('should fail when cursor is combined with page options', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {
              'cursor': 'opaque-token',
              'page': 1,
              'page_size': 100,
            },
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test(
        'should fail when execution_mode preserve is combined with pagination options',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT * FROM users',
              'options': {
                'execution_mode': 'preserve',
                'page': 1,
                'page_size': 100,
              },
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );

      test(
        'should fail when preserve_sql conflicts with execution_mode managed',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT * FROM users',
              'options': {
                'preserve_sql': true,
                'execution_mode': 'managed',
              },
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );
    });

    group('validateBatch', () {
      test('should succeed for valid batch', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
            'params': {'sql': 'SELECT 1'},
          },
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-2',
            'params': {'sql': 'SELECT 2'},
          },
        ];

        final result = validator.validateBatch(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when batch item is not object', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
            'params': {'sql': 'SELECT 1'},
          },
          'invalid',
        ];

        final result = validator.validateBatch(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('index 1'));
      });

      test('should fail when batch item fails single validation', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
            'params': {'sql': 'SELECT 1'},
          },
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': '',
            'id': 'r-2',
          },
        ];

        final result = validator.validateBatch(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('index 1'));
      });

      test('should fail when batch exceeds negotiated limit', () {
        final data = List.generate(
          3,
          (index) => <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-$index',
            'params': {'sql': 'SELECT $index'},
          },
        );

        final result = validator.validateBatch(
          data,
          limits: const TransportLimits(maxBatchSize: 2),
        );

        expect(result.isError(), isTrue);
      });
    });
  });
}
