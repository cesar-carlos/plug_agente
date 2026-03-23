@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('SQL_CLASSIFIER_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _spacePad() {
  final raw = E2EEnv.get('SQL_CLASSIFIER_BENCHMARK_SPACE_PAD')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 0) {
    return 8000;
  }
  return n.clamp(0, 500000);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('SQL_CLASSIFIER_BENCHMARK') != 'true') {
    group('SqlOperationClassifier benchmark', () {
      test(
        'skipped — set SQL_CLASSIFIER_BENCHMARK=true to run',
        () {},
        skip:
            'Defina SQL_CLASSIFIER_BENCHMARK=true no .env para medir classify().',
      );
    });
    return;
  }

  group('SqlOperationClassifier benchmark', () {
    test('should record classify() on padded SELECT FROM', () {
      final pad = _spacePad();
      final iterations = _iterations();
      final sql =
          '${' ' * pad}SELECT${' ' * pad}*${' ' * pad}FROM${' ' * pad}dbo.users';
      final classifier = SqlOperationClassifier();

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final r = classifier.classify(sql);
          expect(r.isSuccess(), isTrue);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('SQL_CLASSIFIER_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('SQL_CLASSIFIER_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}sql_classifier.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'sql_classifier_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'space_pad_segments': pad,
              'sql_chars': sql.length,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'classify_select_from': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
