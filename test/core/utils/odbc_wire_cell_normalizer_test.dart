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

    test('serializes DateTime cells to ISO-8601', () {
      final value = DateTime.utc(2024, 6, 15, 12);

      expect(normalizeOdbcWireCell(value), value.toIso8601String());
    });
  });
}
