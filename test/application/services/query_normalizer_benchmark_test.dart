@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('QUERY_NORMALIZER_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _rows() {
  final raw = E2EEnv.get('QUERY_NORMALIZER_BENCHMARK_ROWS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 4000;
  }
  return n.clamp(1, 100000);
}

QueryResponse _buildResponse(int rowCount) {
  final rows = List<Map<String, dynamic>>.generate(
    rowCount,
    (int i) => <String, dynamic>{
      'Weird COL Name $i': i,
      'x': 'v$i',
    },
    growable: false,
  );
  return QueryResponse(
    id: 'bench',
    requestId: 'req',
    agentId: 'agent',
    data: rows,
    timestamp: DateTime.utc(2020),
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('QUERY_NORMALIZER_BENCHMARK') != 'true') {
    group('QueryNormalizerService benchmark', () {
      test(
        'skipped — set QUERY_NORMALIZER_BENCHMARK=true to run',
        () {},
        skip:
            'Defina QUERY_NORMALIZER_BENCHMARK=true no .env para medir normalize().',
      );
    });
    return;
  }

  group('QueryNormalizerService benchmark', () {
    test('should record normalize() wall time for wide rows', () {
      final rowCount = _rows();
      final iterations = _iterations();
      final response = _buildResponse(rowCount);
      final service = QueryNormalizerService(QueryNormalizer());

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final out = service.normalize(response);
          expect(out.data, hasLength(rowCount));
        },
        iterations: iterations,
      );

      if (E2EEnv.get('QUERY_NORMALIZER_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('QUERY_NORMALIZER_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}query_normalizer.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'query_normalizer_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'rows': rowCount,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'normalize_query_response': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
