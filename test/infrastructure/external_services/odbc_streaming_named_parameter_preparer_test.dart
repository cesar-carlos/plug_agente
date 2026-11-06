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

    test('ignores placeholders inside escaped bracket identifiers', () {
      const sql = 'SELECT [x]]:hidden] FROM items WHERE id = :id';
      final result = preparer.prepare(sql: sql, parameters: const {'id': 7});

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().sql, sql);
      expect(result.getOrThrow().parameters, {'id': 7});
    });

    test('accepts repeated and null parameters from an immutable map', () {
      final parameters = Map<String, dynamic>.unmodifiable({'id': null, 'unused': 9});
      final result = preparer.prepare(
        sql: 'SELECT :id AS a, :id AS b',
        parameters: parameters,
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().parameters, {'id': null, 'unused': 9});
      expect(parameters, {'id': null, 'unused': 9});
    });

    test('reports missing repeated parameters once in occurrence order', () {
      final result = preparer.prepare(
        sql: 'SELECT :second, :first, :second',
        parameters: const {'unused': 9},
      );

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull().toString(),
        contains('Missing required parameters: second, first'),
      );
    });
  });
}
