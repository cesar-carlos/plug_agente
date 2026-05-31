import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

void main() {
  group('mapOdbcRowToStreamingMap', () {
    test('should map ODBC row vectors into streaming row maps', () {
      final row = mapOdbcRowToStreamingMap(
        const <String>['id', 'name'],
        const <dynamic>[1, 'a'],
      );

      expect(row, <String, dynamic>{'id': 1, 'name': 'a'});
    });
  });
}
