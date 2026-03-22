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

  group('selectComparableE2eBenchmarkRecords', () {
    test(
      'should keep only records with matching target, build and profile',
      () {
        final selected = selectComparableE2eBenchmarkRecords(
          records: <Map<String, dynamic>>[
            <String, dynamic>{
              'target_label': 'primary',
              'build_mode': 'debug',
              'database_hosting': 'local',
              'benchmark_profile': <String, dynamic>{
                'pool_mode': 'lease',
                'pool_size': 2,
              },
              'cases': <String, dynamic>{},
            },
            <String, dynamic>{
              'target_label': 'primary',
              'build_mode': 'debug',
              'database_hosting': 'remote',
              'benchmark_profile': <String, dynamic>{
                'pool_mode': 'lease',
                'pool_size': 2,
              },
              'cases': <String, dynamic>{},
            },
            <String, dynamic>{
              'target_label': 'primary',
              'build_mode': 'profile',
              'database_hosting': 'local',
              'benchmark_profile': <String, dynamic>{
                'pool_mode': 'lease',
                'pool_size': 2,
              },
              'cases': <String, dynamic>{},
            },
          ],
          targetLabel: 'primary',
          buildMode: 'debug',
          benchmarkProfile: <String, dynamic>{
            'pool_mode': 'lease',
            'pool_size': 2,
          },
          databaseHosting: 'local',
        );

        expect(selected, hasLength(1));
        expect(selected.single['database_hosting'], 'local');
      },
    );
  });

  group('assertE2eBenchmarkWithinRegressionBudget', () {
    test('should pass when current cases stay within regression budget', () {
      assertE2eBenchmarkWithinRegressionBudget(
        cases: <String, dynamic>{
          'rpc_sql_execute_materialized': <String, dynamic>{'median_ms': 112},
        },
        baselineRecords: <Map<String, dynamic>>[
          <String, dynamic>{
            'cases': <String, dynamic>{
              'rpc_sql_execute_materialized': <String, dynamic>{
                'median_ms': 100,
              },
            },
          },
          <String, dynamic>{
            'cases': <String, dynamic>{
              'rpc_sql_execute_materialized': <String, dynamic>{
                'median_ms': 110,
              },
            },
          },
        ],
        maxRegressionPercent: 10,
        maxRegressionMs: 5,
      );
    });

    test('should fail when current case exceeds regression budget', () {
      expect(
        () => assertE2eBenchmarkWithinRegressionBudget(
          cases: <String, dynamic>{
            'rpc_sql_execute_multi_result': <String, dynamic>{'median_ms': 140},
          },
          baselineRecords: <Map<String, dynamic>>[
            <String, dynamic>{
              'cases': <String, dynamic>{
                'rpc_sql_execute_multi_result': <String, dynamic>{
                  'median_ms': 100,
                },
              },
            },
          ],
          maxRegressionPercent: 10,
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('should fail when there are no comparable baseline records', () {
      expect(
        () => assertE2eBenchmarkWithinRegressionBudget(
          cases: <String, dynamic>{
            'rpc_sql_execute_streaming': <String, dynamic>{'median_ms': 20},
          },
          baselineRecords: const <Map<String, dynamic>>[],
          maxRegressionPercent: 15,
        ),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
