import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_named_parameter_preparer.dart';

void main() {
  const preparer = OdbcStreamingNamedParameterPreparer.instance;

  group('OdbcStreamingNamedParameterPreparer', () {
    test('passes through parameterless SQL', () {
      final result = preparer.prepare(
        sql: 'SELECT id FROM users',
      );
      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().parameters, isNull);
    });

    test('keeps named-parameter SQL for streamQueryNamed', () {
      final result = preparer.prepare(
        sql: 'SELECT id FROM users WHERE id = :id',
        parameters: const {'id': 1},
      );
      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().sql, contains(':id'));
    });

    test('fails when a named parameter is missing', () {
      final result = preparer.prepare(
        sql: 'SELECT id FROM users WHERE id = :id',
        parameters: const {'other': 1},
      );
      expect(result.isError(), isTrue);
    });
  });
}
