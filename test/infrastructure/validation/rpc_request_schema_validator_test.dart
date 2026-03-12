import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for notification (null id)', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': null,
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

      test('should succeed when id is number', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 1,
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });
    });

    group('validateBatch', () {
      test('should succeed for valid batch', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
          },
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-2',
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
    });
  });
}
