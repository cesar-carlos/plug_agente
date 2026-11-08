import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_native_bulk_insert_builder.dart';

void main() {
  for (final type in BulkInsertColumnType.values) {
    final nativeType = BulkColumnType.values.byName(type.name);
    final maxLen = switch (type) {
      BulkInsertColumnType.text || BulkInsertColumnType.decimal || BulkInsertColumnType.binary => 64,
      _ => 0,
    };
    final value = switch (type) {
      BulkInsertColumnType.i32 => 42,
      BulkInsertColumnType.i64 => 1 << 40,
      BulkInsertColumnType.text => 'ação',
      BulkInsertColumnType.decimal => '123.45',
      BulkInsertColumnType.binary => Uint8List.fromList([0, 255, 1]),
      BulkInsertColumnType.timestamp => BulkTimestamp.fromDateTime(DateTime.utc(2026)),
    };
    for (final nullIndices in [
      <int>{},
      {0},
      {1},
      {2},
      {0, 1, 2},
      {7, 8, 16},
    ]) {
      test('preserves ${type.name} payload with nulls at $nullIndices', () {
        final rowCount = nullIndices.contains(16) ? 17 : 3;
        final rows = List<List<dynamic>>.generate(
          rowCount,
          (index) => [if (nullIndices.contains(index)) null else value],
        );
        final expected = BulkInsertBuilder()
          ..table('fixture')
          ..addColumn('value', nativeType, nullable: true, maxLen: maxLen);
        rows.forEach(expected.addRow);
        final actual = OdbcNativeBulkInsertBuilder.fromRequest(
          BulkInsertRequest(
            table: 'fixture',
            columns: [BulkInsertColumn(name: 'value', type: type, nullable: true, maxLen: maxLen)],
            rows: rows,
          ),
        );
        expect(actual.build(), orderedEquals(expected.build()));
        expect(actual.rowCount, rowCount);
      });
    }
    test('rejects nulls in required ${type.name} columns', () {
      expect(
        () => OdbcNativeBulkInsertBuilder.fromRequest(
          BulkInsertRequest(
            table: 'fixture',
            columns: [BulkInsertColumn(name: 'value', type: type)],
            rows: [
              [value],
              [null],
            ],
          ),
        ).build(),
        throwsStateError,
      );
    });
  }

  test('preserves numeric and boolean coercions in text payloads', () {
    final actual = OdbcNativeBulkInsertBuilder.fromRequest(
      const BulkInsertRequest(
        table: 't',
        columns: [BulkInsertColumn(name: 'value', type: BulkInsertColumnType.text)],
        rows: [
          [42],
          [1.5],
          [true],
          [false],
        ],
      ),
    );
    final expected = BulkInsertBuilder()
      ..table('t')
      ..addColumn('value', BulkColumnType.text)
      ..addRow(['42'])
      ..addRow(['1.5'])
      ..addRow(['true'])
      ..addRow(['false']);
    expect(actual.build(), orderedEquals(expected.build()));
  });

  test('enforces text limits in UTF-8 bytes rather than characters', () {
    BulkInsertRequest request(int maxLen) => BulkInsertRequest(
      table: 't',
      columns: [BulkInsertColumn(name: 'value', type: BulkInsertColumnType.text, maxLen: maxLen)],
      rows: const [
        ['ação'],
      ],
    );
    final expected = BulkInsertBuilder()
      ..table('t')
      ..addColumn('value', BulkColumnType.text, maxLen: 6)
      ..addRow(['ação']);
    expect(OdbcNativeBulkInsertBuilder.fromRequest(request(6)).build(), orderedEquals(expected.build()));
    expect(
      () => OdbcNativeBulkInsertBuilder.fromRequest(request(5)),
      throwsA(isA<ArgumentError>().having((error) => error.message, 'message', contains('UTF-8'))),
    );
  });

  test('uses columnar path for whole-number doubles in i32 columns', () {
    const request = BulkInsertRequest(
      table: 't',
      columns: [
        BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
      ],
      rows: [
        [1.0],
        [2.0],
      ],
    );

    final builder = OdbcNativeBulkInsertBuilder.fromRequest(request);
    final expected = BulkInsertBuilder()
      ..table('t')
      ..addColumn('id', BulkColumnType.i32)
      ..addRow([1])
      ..addRow([2]);
    expect(builder.build(), orderedEquals(expected.build()));
  });
}
