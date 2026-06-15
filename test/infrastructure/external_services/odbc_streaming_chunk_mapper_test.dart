import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

void main() {
  group('normalizeOdbcStreamingCell', () {
    test('materializes LazyString values', () {
      final lazy = LazyString(Uint8List.fromList(utf8.encode('Cliente A')));

      expect(normalizeOdbcStreamingCell(lazy), 'Cliente A');
    });

    test('encodes binary cells as base64', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      expect(normalizeOdbcStreamingCell(bytes), base64Encode(bytes));
    });

    test('serializes DateTime cells to ISO-8601', () {
      final value = DateTime.utc(2024, 6, 15, 12);

      expect(normalizeOdbcStreamingCell(value), value.toIso8601String());
    });

    test('passes SQL Anywhere text timestamps through unchanged', () {
      expect(
        normalizeOdbcStreamingCell('2024-06-15 12:00:00'),
        '2024-06-15 12:00:00',
      );
    });
  });

  group('mapOdbcRowToStreamingMap', () {
    test('should map ODBC row vectors into streaming row maps', () {
      final row = mapOdbcRowToStreamingMap(
        const <String>['id', 'name'],
        const <dynamic>[1, 'a'],
      );

      expect(row, <String, dynamic>{'id': 1, 'name': 'a'});
    });

    test('should normalize Cliente-like SQL Anywhere row values', () {
      final lazyNome = LazyString(Uint8List.fromList(utf8.encode('ACME')));
      final foto = Uint8List.fromList(<int>[9, 8, 7]);

      final row = mapOdbcRowToStreamingMap(
        const <String>['CodCliente', 'Nome', 'DataCadastro', 'Foto'],
        <dynamic>[1, lazyNome, '2024-06-15 12:00:00', foto],
      );

      expect(row, <String, dynamic>{
        'CodCliente': 1,
        'Nome': 'ACME',
        'DataCadastro': '2024-06-15 12:00:00',
        'Foto': base64Encode(foto),
      });
    });
  });

  group('mapQueryRowsToChunks', () {
    test('should emit a single chunk when native batch fits fetch size', () {
      final chunks = mapQueryRowsToChunks(
        const OdbcStreamingChunkMapperInput(
          columns: <String>['id'],
          rows: <List<dynamic>>[
            <dynamic>[1],
            <dynamic>[2],
          ],
          fetchSize: 500,
        ),
      );

      expect(chunks, hasLength(1));
      expect(chunks.single, [
        <String, dynamic>{'id': 1},
        <String, dynamic>{'id': 2},
      ]);
    });

    test('should split rows when native batch exceeds fetch size', () {
      final chunks = mapQueryRowsToChunks(
        const OdbcStreamingChunkMapperInput(
          columns: <String>['id'],
          rows: <List<dynamic>>[
            <dynamic>[1],
            <dynamic>[2],
            <dynamic>[3],
          ],
          fetchSize: 2,
        ),
      );

      expect(chunks, hasLength(2));
      expect(chunks[0].length, 2);
      expect(chunks[1].length, 1);
    });

    test('should return no chunks for empty input', () {
      final chunks = mapQueryRowsToChunks(
        const OdbcStreamingChunkMapperInput(
          columns: <String>['id'],
          rows: <List<dynamic>>[],
          fetchSize: 100,
        ),
      );

      expect(chunks, isEmpty);
    });
  });
}
