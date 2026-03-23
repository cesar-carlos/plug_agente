@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('IDEMPOTENCY_STORE_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _entries() {
  final raw = E2EEnv.get('IDEMPOTENCY_STORE_BENCHMARK_ENTRIES')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 500;
  }
  return n.clamp(1, 50000);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('IDEMPOTENCY_STORE_BENCHMARK') != 'true') {
    group('InMemoryIdempotencyStore benchmark', () {
      test(
        'skipped — set IDEMPOTENCY_STORE_BENCHMARK=true to run',
        () {},
        skip:
            'Defina IDEMPOTENCY_STORE_BENCHMARK=true no .env para medir set/get.',
      );
    });
    return;
  }

  group('InMemoryIdempotencyStore benchmark', () {
    test('should record set+get cycle wall time', () {
      final entryCount = _entries();
      final iterations = _iterations();
      const ttl = Duration(minutes: 5);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final store = InMemoryIdempotencyStore(
            maxEntries: entryCount + 64,
          );
          for (var i = 0; i < entryCount; i++) {
            store.set(
              'key-$i',
              RpcResponse.success(
                id: i,
                result: <String, dynamic>{'n': i},
              ),
              ttl,
            );
          }
          for (var i = 0; i < entryCount; i++) {
            final r = store.get('key-$i');
            expect(r, isNotNull);
          }
        },
        iterations: iterations,
      );

      if (E2EEnv.get('IDEMPOTENCY_STORE_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('IDEMPOTENCY_STORE_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}idempotency_store.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'idempotency_store_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'entries': entryCount,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'set_get_cycle': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
