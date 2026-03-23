@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('JSON_SIZE_HEURISTIC_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _mapKeys() {
  final raw = E2EEnv.get('JSON_SIZE_HEURISTIC_BENCHMARK_MAP_KEYS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 8000;
  }
  return n.clamp(1, 200000);
}

int _budgetBytes() {
  final raw = E2EEnv.get('JSON_SIZE_HEURISTIC_BENCHMARK_BUDGET')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return jsonPayloadIsolateEncodeThresholdBytes;
  }
  return n.clamp(1024, 16 * 1024 * 1024);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('JSON_SIZE_HEURISTIC_BENCHMARK') != 'true') {
    group('jsonTreeLikelyExceedsByteBudget benchmark', () {
      test(
        'skipped — set JSON_SIZE_HEURISTIC_BENCHMARK=true to run',
        () {},
        skip:
            'Defina JSON_SIZE_HEURISTIC_BENCHMARK=true para medir a heurística.',
      );
    });
    return;
  }

  group('jsonTreeLikelyExceedsByteBudget benchmark', () {
    test('should record walk over wide string-key map', () {
      final keys = _mapKeys();
      final budget = _budgetBytes();
      final iterations = _iterations();
      final tree = <String, dynamic>{
        for (var i = 0; i < keys; i++) 'k$i': i,
      };

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final exceeds = jsonTreeLikelyExceedsByteBudget(tree, budget);
          expect(exceeds, isTrue);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('JSON_SIZE_HEURISTIC_BENCHMARK_RECORD') == 'true') {
        final custom =
            E2EEnv.get('JSON_SIZE_HEURISTIC_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}json_size_heuristic.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'json_size_heuristic_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'map_keys': keys,
              'budget_bytes': budget,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'likely_exceeds_budget': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
