import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';

import '../../tool/benchmarks/native_odbc_benchmark.dart';
import '../../tool/benchmarks/odbc_benchmark_fixture.dart';

void main() {
  test('should verify all rows rather than accepting empty or truncated results', () {
    final rows = [
      for (var id = 1; id <= 8000; id++) <dynamic>[id, 'benchmark-row-$id'],
    ];
    expect(() => validateBenchmarkRows(rows), returnsNormally);
    expect(() => validateBenchmarkRows([]), throwsStateError);
    expect(() => validateBenchmarkRows(rows.sublist(1)), throwsStateError);
    rows[300][1] = 'corrupted';
    expect(() => validateBenchmarkRows(rows), throwsStateError);
  });

  test('should read the actual wire version and compression flag', () {
    final bytes = Uint8List(19);
    final header = ByteData.sublistView(bytes)
      ..setUint32(0, BinaryProtocolParser.magic, Endian.little)
      ..setUint16(4, 1, Endian.little);
    expect(observedResultEncoding(bytes), 'rowMajor');
    header.setUint16(4, 2, Endian.little);
    expect(observedResultEncoding(bytes), 'columnar');
    bytes[14] = 1;
    expect(observedResultEncoding(bytes), 'columnarCompressed');
  });
}
