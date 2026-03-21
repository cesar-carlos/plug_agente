import 'package:flutter_test/flutter_test.dart';

import 'e2e_benchmark_assertions.dart';

void main() {
  group('assertE2eBenchmarkWithinThresholds', () {
    test('should pass when median_ms is within threshold', () {
      assertE2eBenchmarkWithinThresholds(
        cases: <String, dynamic>{
          'rpc_sql_execute_materialized': <String, dynamic>{
            'median_ms': 50,
            'samples_ms': <int>[50],
          },
        },
        thresholds: <String, int>{'rpc_sql_execute_materialized': 100},
      );
    });

    test('should use elapsed_ms when median_ms is absent', () {
      assertE2eBenchmarkWithinThresholds(
        cases: <String, dynamic>{
          'rpc_sql_execute_multi_result': <String, dynamic>{
            'elapsed_ms': 120,
          },
        },
        thresholds: <String, int>{'rpc_sql_execute_multi_result': 200},
      );
    });

    test('should fail when median_ms exceeds threshold', () {
      expect(
        () => assertE2eBenchmarkWithinThresholds(
          cases: <String, dynamic>{
            'rpc_sql_execute_batch_reads': <String, dynamic>{'median_ms': 500},
          },
          thresholds: <String, int>{'rpc_sql_execute_batch_reads': 100},
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('should ignore threshold keys missing from cases', () {
      assertE2eBenchmarkWithinThresholds(
        cases: <String, dynamic>{
          'rpc_sql_execute_materialized': <String, dynamic>{'median_ms': 10},
        },
        thresholds: <String, int>{
          'rpc_sql_execute_materialized': 100,
          'rpc_sql_execute_streaming': 50,
        },
      );
    });

    test('should ignore cases that are not maps', () {
      assertE2eBenchmarkWithinThresholds(
        cases: <String, dynamic>{
          'rpc_sql_execute_materialized': 'not-a-map',
        },
        thresholds: <String, int>{'rpc_sql_execute_materialized': 1},
      );
    });
  });
}
