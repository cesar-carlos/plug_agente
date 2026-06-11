import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validation_support.dart';

void main() {
  group('RpcRequestSchemaValidationSupport', () {
    test('invalidRequest attaches invalidRequest rpc error code', () {
      final result = RpcRequestSchemaValidationSupport.invalidRequest('bad envelope');
      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.ValidationFailure;
      expect(failure.message, 'bad envelope');
      expect(failure.context['rpc_error_code'], RpcErrorCode.invalidRequest);
    });

    test('invalidParams attaches invalidParams rpc error code', () {
      final result = RpcRequestSchemaValidationSupport.invalidParams('bad params');
      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.ValidationFailure;
      expect(failure.context['rpc_error_code'], RpcErrorCode.invalidParams);
    });

    test('tryParseNonNegativeInt accepts int and rounded double', () {
      expect(RpcRequestSchemaValidationSupport.tryParseNonNegativeInt(3), 3);
      expect(RpcRequestSchemaValidationSupport.tryParseNonNegativeInt(3.0), 3);
      expect(RpcRequestSchemaValidationSupport.tryParseNonNegativeInt(-1), isNull);
      expect(RpcRequestSchemaValidationSupport.tryParseNonNegativeInt(1.5), isNull);
    });

    test('validateMeta rejects unsupported keys', () {
      final result = RpcRequestSchemaValidationSupport.validateMeta(<String, dynamic>{
        'unknown': 'value',
      });
      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull()!.toString(),
        contains('unsupported properties'),
      );
    });
  });
}
