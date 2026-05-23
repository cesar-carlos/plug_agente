import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_config.dart';

void main() {
  group('resultEncodingFromString', () {
    test('should default blank values to rowMajor', () {
      expect(resultEncodingFromString(null), ResultEncoding.rowMajor);
      expect(resultEncodingFromString(''), ResultEncoding.rowMajor);
      expect(resultEncodingFromString('row_major'), ResultEncoding.rowMajor);
      expect(resultEncodingFromString('0'), ResultEncoding.rowMajor);
    });

    test('should parse columnar aliases', () {
      expect(resultEncodingFromString('columnar'), ResultEncoding.columnar);
      expect(resultEncodingFromString('columnar-v2'), ResultEncoding.columnar);
      expect(resultEncodingFromString('1'), ResultEncoding.columnar);
    });

    test('should parse columnar compressed aliases', () {
      expect(resultEncodingFromString('columnarCompressed'), ResultEncoding.columnarCompressed);
      expect(resultEncodingFromString('columnar_compressed'), ResultEncoding.columnarCompressed);
      expect(resultEncodingFromString('2'), ResultEncoding.columnarCompressed);
    });

    test('should return null for invalid values', () {
      expect(resultEncodingFromString('not-valid'), isNull);
    });
  });
}
