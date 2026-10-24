import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/utils/odbc_wire_cell_normalizer.dart';

void main() {
  group('normalizeOdbcWireCell', () {
    test('materializes LazyString values', () {
      final lazy = LazyString(Uint8List.fromList(utf8.encode('Cliente A')));

      expect(normalizeOdbcWireCell(lazy), 'Cliente A');
    });

    test('encodes binary cells as base64', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      expect(normalizeOdbcWireCell(bytes), base64Encode(bytes));
    });

    test('leaves plain JSON values unchanged', () {
      const value = 'ana';
      const number = 7;
      const flag = true;

      expect(odbcWireCellNeedsMaterialization(value), isFalse);
      expect(odbcWireCellNeedsMaterialization(null), isFalse);
      expect(odbcWireCellNeedsMaterialization(number), isFalse);
      expect(odbcWireCellNeedsMaterialization(flag), isFalse);
      expect(identical(normalizeOdbcWireCell(value), value), isTrue);
      expect(identical(normalizeOdbcWireCell(number), number), isTrue);
      expect(identical(normalizeOdbcWireCell(flag), flag), isTrue);
      expect(normalizeOdbcWireCell(null), isNull);
    });

    test('encodes a non-uint8 byte list as base64', () {
      final bytes = <int>[1, 2, 3];

      expect(normalizeOdbcWireCell(bytes), base64Encode(bytes));
    });

    test('flags lazy, timestamp and binary cells for materialization', () {
      final lazy = LazyString(Uint8List.fromList(utf8.encode('Cliente A')));
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      expect(odbcWireCellNeedsMaterialization(lazy), isTrue);
      expect(odbcWireCellNeedsMaterialization(DateTime.utc(2024, 6, 15)), isTrue);
      expect(odbcWireCellNeedsMaterialization(bytes), isTrue);
      expect(odbcWireCellNeedsMaterialization(<int>[1, 2, 3]), isTrue);
    });

    test('serializes DateTime cells to ISO-8601', () {
      final value = DateTime.utc(2024, 6, 15, 12);

      expect(normalizeOdbcWireCell(value), value.toIso8601String());
    });
  });
}
