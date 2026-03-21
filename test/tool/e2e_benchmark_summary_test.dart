import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_benchmark_summary.dart';

void main() {
  group('e2eBenchmarkLatencyMsFromCase', () {
    test('should prefer median_ms over elapsed_ms', () {
      check(
        e2eBenchmarkLatencyMsFromCase(<String, dynamic>{
          'median_ms': 10,
          'elapsed_ms': 99,
        }),
      ).equals(10);
    });

    test('should fall back to elapsed_ms', () {
      check(
        e2eBenchmarkLatencyMsFromCase(<String, dynamic>{'elapsed_ms': 42}),
      ).equals(42);
    });

    test('should return null for non-map', () {
      check(e2eBenchmarkLatencyMsFromCase(null)).isNull();
      check(e2eBenchmarkLatencyMsFromCase(1)).isNull();
    });
  });

  group('parseE2eBenchmarkJsonlLines', () {
    test('should skip empty and invalid lines', () {
      final records = parseE2eBenchmarkJsonlLines(<String>[
        '',
        'not json',
        jsonEncode(<String, dynamic>{
          'target_label': 'primary',
          'cases': <String, dynamic>{},
        }),
      ]);
      check(records.length).equals(1);
      check(records.first['target_label']).equals('primary');
    });
  });

  group('formatE2eBenchmarkSummary', () {
    test('should average last window per case', () {
      final r1 = <String, dynamic>{
        'target_label': 'primary',
        'run_id': 'a',
        'recorded_at': '2024-01-01T00:00:00Z',
        'cases': <String, dynamic>{
          'rpc_sql_execute_materialized': <String, dynamic>{'median_ms': 100},
        },
      };
      final r2 = <String, dynamic>{
        'target_label': 'primary',
        'run_id': 'b',
        'recorded_at': '2024-01-02T00:00:00Z',
        'cases': <String, dynamic>{
          'rpc_sql_execute_materialized': <String, dynamic>{'median_ms': 200},
        },
      };
      final lines = formatE2eBenchmarkSummary(
        records: <Map<String, dynamic>>[r1, r2],
        filePathLabel: 'mem.jsonl',
        totalRawLines: 2,
      );
      check(lines.join('\n')).contains('avg_last_2_ms=150.0');
      check(lines.join('\n')).contains('last_median_ms=200.0');
    });

    test('should return message when records empty', () {
      final lines = formatE2eBenchmarkSummary(
        records: <Map<String, dynamic>>[],
        filePathLabel: 'x',
        totalRawLines: 0,
      );
      check(lines.first).contains('No valid JSON');
    });
  });
}
