@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

const int _defaultWasteBytes = 300 * 1024;
const int _maxWasteBytes = 2 * 1024 * 1024;

int _parseWasteBytes() {
  final raw = E2EEnv.get(
    'IDEMPOTENCY_FINGERPRINT_BENCHMARK_WASTE_BYTES',
  )?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n <= 0) {
    return _defaultWasteBytes;
  }
  return n.clamp(1, _maxWasteBytes);
}

int _parseIterations() {
  final raw = E2EEnv.get(
    'IDEMPOTENCY_FINGERPRINT_BENCHMARK_ITERATIONS',
  )?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 64);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('IDEMPOTENCY_FINGERPRINT_BENCHMARK') != 'true') {
    group('Idempotency fingerprint benchmark', () {
      test(
        'skipped — set IDEMPOTENCY_FINGERPRINT_BENCHMARK=true to run',
        () {},
        skip:
            'Defina IDEMPOTENCY_FINGERPRINT_BENCHMARK=true no .env para medir hash de params grandes.',
      );
    });
    return;
  }

  group('Idempotency fingerprint benchmark', () {
    test(
      'should record resolveIdempotencyFingerprint latency for large params',
      () async {
        final wasteBytes = _parseWasteBytes();
        final benchWaste = String.fromCharCodes(
          List<int>.filled(wasteBytes, 0x41),
        );
        final params = <String, dynamic>{
          'sql': 'SELECT 1',
          'bench_waste': benchWaste,
        };

        final iterations = _parseIterations();
        final stats = await E2eBenchmarkStats.measureAsync(
          () async {
            final fp = await resolveIdempotencyFingerprint(
              'rpc.sql.execute',
              params,
            );
            expect(fp, hasLength(64));
          },
          iterations: iterations,
        );

        if (E2EEnv.get('IDEMPOTENCY_FINGERPRINT_BENCHMARK_RECORD') == 'true') {
          final custom = E2EEnv.get(
            'IDEMPOTENCY_FINGERPRINT_BENCHMARK_FILE',
          )?.trim();
          final relative = (custom != null && custom.isNotEmpty)
              ? custom
              : 'benchmark${Platform.pathSeparator}idempotency_fingerprint.jsonl';
          appendE2eBenchmarkRecord(
            file: resolveE2eBenchmarkOutputFile(relative),
            record: <String, dynamic>{
              'schema_version': 2,
              'suite': 'idempotency_fingerprint_benchmark',
              'run_id': const Uuid().v4(),
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
              'benchmark_profile': <String, dynamic>{
                'waste_bytes': wasteBytes,
                'iterations': iterations,
              },
              'cases': <String, dynamic>{
                'resolve_idempotency_fingerprint_large_params': stats.toJson(),
              },
            },
          );
        }
      },
    );
  });
}
