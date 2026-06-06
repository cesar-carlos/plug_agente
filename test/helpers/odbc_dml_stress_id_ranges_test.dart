import 'package:flutter_test/flutter_test.dart';

import 'odbc_dml_stress_id_ranges.dart';

void main() {
  group('buildOdbcDmlStressIdRanges', () {
    test('partitions 2000 rows across 8 workers without overlap', () {
      final ranges = buildOdbcDmlStressIdRanges(2000, 8);

      expect(ranges, hasLength(8));
      expect(ranges.first.start, 1);
      expect(ranges.first.end, 250);
      expect(ranges.last.start, 1751);
      expect(ranges.last.end, 2000);

      final ids = <int>{};
      for (final range in ranges) {
        for (var id = range.start; id <= range.end; id++) {
          expect(ids.add(id), isTrue, reason: 'duplicate local id $id');
        }
      }
      expect(ids.length, 2000);
      expect(ids.first, 1);
      expect(ids.last, 2000);
    });

    test('partitions 1000 rows across 8 workers', () {
      final ranges = buildOdbcDmlStressIdRanges(1000, 8);

      expect(ranges, hasLength(8));
      expect(ranges.map((r) => r.end - r.start + 1).fold<int>(0, (a, b) => a + b), 1000);
    });

    test('covers every row when concurrency exceeds rowCount', () {
      final ranges = buildOdbcDmlStressIdRanges(100, 32);

      expect(ranges, hasLength(32));
      final ids = <int>{};
      for (final range in ranges) {
        for (var id = range.start; id <= range.end; id++) {
          expect(ids.add(id), isTrue, reason: 'duplicate local id $id');
        }
      }
      expect(ids.length, 100);
    });
  });

  group('odbcDmlStressRowId', () {
    test('offsets ids per iteration', () {
      expect(
        odbcDmlStressRowId(iteration: 0, rowCount: 2000, localId: 1),
        1,
      );
      expect(
        odbcDmlStressRowId(iteration: 1, rowCount: 2000, localId: 1),
        2001,
      );
    });
  });

  group('odbcDmlStressBatchTimeoutMs', () {
    test('scales above default for 2000 rows and concurrency 8', () {
      final timeout = odbcDmlStressBatchTimeoutMs(rowCount: 2000, concurrency: 8);
      expect(timeout, greaterThan(60000));
    });
  });
}
