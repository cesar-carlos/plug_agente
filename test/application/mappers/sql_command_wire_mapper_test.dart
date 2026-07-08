import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/mappers/sql_command_wire_mapper.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';

void main() {
  const mapper = SqlCommandWireMapper();

  group('SqlCommandWireMapper', () {
    test('fromJson and toJson round-trip SqlCommand', () {
      const command = SqlCommand(
        sql: 'SELECT 1',
        params: {'id': 42},
      );

      final json = mapper.toJson(command);
      final restored = mapper.fromJson(json);

      expect(restored.sql, command.sql);
      expect(restored.params, command.params);
      expect(json, {
        'sql': 'SELECT 1',
        'params': {'id': 42},
      });
    });

    test('resultFromJson accepts snake_case and camelCase metadata keys', () {
      final fromSnakeCase = mapper.resultFromJson({
        'index': 0,
        'ok': true,
        'rows': [
          {'id': 1},
        ],
        'row_count': 1,
        'affected_rows': 2,
        'column_metadata': [
          {'name': 'id'},
        ],
      });
      final fromCamelCase = mapper.resultFromJson({
        'index': 1,
        'ok': false,
        'error': 'boom',
        'rowCount': 3,
        'affectedRows': 4,
        'columnMetadata': [
          {'name': 'name'},
        ],
      });

      expect(fromSnakeCase.index, 0);
      expect(fromSnakeCase.ok, isTrue);
      expect(fromSnakeCase.rowCount, 1);
      expect(fromSnakeCase.affectedRows, 2);
      expect(fromSnakeCase.columnMetadata, [
        {'name': 'id'},
      ]);

      expect(fromCamelCase.index, 1);
      expect(fromCamelCase.ok, isFalse);
      expect(fromCamelCase.error, 'boom');
      expect(fromCamelCase.rowCount, 3);
      expect(fromCamelCase.affectedRows, 4);
      expect(fromCamelCase.columnMetadata, [
        {'name': 'name'},
      ]);
    });

    test('resultToJson uses snake_case wire keys', () {
      final json = mapper.resultToJson(
        SqlCommandResult.success(
          index: 0,
          rows: const [
            {'id': 1},
          ],
          affectedRows: 2,
          columnMetadata: const [
            {'name': 'id'},
          ],
        ),
      );

      expect(json['index'], 0);
      expect(json['ok'], isTrue);
      expect(json['rows'], [
        {'id': 1},
      ]);
      expect(json['row_count'], 1);
      expect(json['affected_rows'], 2);
      expect(json['column_metadata'], [
        {'name': 'id'},
      ]);
    });

    test('optionsFromJson applies defaults and optionsToJson round-trip', () {
      final defaults = mapper.optionsFromJson({});
      expect(defaults.timeoutMs, 30000);
      expect(defaults.maxRows, 50000);
      expect(defaults.transaction, isFalse);
      expect(defaults.maxParallelReadOnlyBatchItems, 1);

      const options = SqlExecutionOptions(
        timeoutMs: 1000,
        maxRows: 100,
        transaction: true,
        maxParallelReadOnlyBatchItems: 4,
      );
      final restored = mapper.optionsFromJson(mapper.optionsToJson(options));
      expect(restored.timeoutMs, options.timeoutMs);
      expect(restored.maxRows, options.maxRows);
      expect(restored.transaction, options.transaction);
      expect(restored.maxParallelReadOnlyBatchItems, options.maxParallelReadOnlyBatchItems);
    });
  });
}
