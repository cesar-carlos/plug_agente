@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('CANONICALIZE_JSON_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _mapSize() {
  final raw = E2EEnv.get('CANONICALIZE_JSON_BENCHMARK_MAP_KEYS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 400;
  }
  return n.clamp(1, 20000);
}

Map<String, dynamic> _buildShuffledKeysMap(int keys) {
  final entries = List<MapEntry<String, int>>.generate(
    keys,
    (int i) => MapEntry('k${keys - 1 - i}', i),
  );
  return Map<String, dynamic>.fromEntries(entries);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('CANONICALIZE_JSON_BENCHMARK') != 'true') {
    group('canonicalizeJsonValueForIdempotency benchmark', () {
      test(
        'skipped — set CANONICALIZE_JSON_BENCHMARK=true to run',
        () {},
        skip:
            'Defina CANONICALIZE_JSON_BENCHMARK=true no .env para medir canonicalização.',
      );
    });
    return;
  }

  group('canonicalizeJsonValueForIdempotency benchmark', () {
    test('should record canonicalize wall time for wide string-key map', () {
      final keyCount = _mapSize();
      final iterations = _iterations();
      final input = _buildShuffledKeysMap(keyCount);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final out = canonicalizeJsonValueForIdempotency(input);
          expect(out, isA<Map<String, dynamic>>());
          final map = out as Map<String, dynamic>;
          expect(map.length, keyCount);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('CANONICALIZE_JSON_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('CANONICALIZE_JSON_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}canonicalize_json.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'canonicalize_json_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'map_keys': keyCount,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'canonicalize_string_key_map': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
