@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('RPC_REQUEST_GUARD_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 8;
  }
  return n.clamp(3, 64);
}

int _evaluations() {
  final raw = E2EEnv.get('RPC_REQUEST_GUARD_BENCHMARK_EVALUATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 10) {
    return 8000;
  }
  return n.clamp(10, 200000);
}

int _replayCap() {
  final raw = E2EEnv.get('RPC_REQUEST_GUARD_BENCHMARK_REPLAY_CAP')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 8) {
    return 128;
  }
  return n.clamp(8, 65536);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('RPC_REQUEST_GUARD_BENCHMARK') != 'true') {
    group('RpcRequestGuard benchmark', () {
      test(
        'skipped — set RPC_REQUEST_GUARD_BENCHMARK=true to run',
        () {},
        skip:
            'Defina RPC_REQUEST_GUARD_BENCHMARK=true para medir evaluate + eviction.',
      );
    });
    return;
  }

  group('RpcRequestGuard benchmark', () {
    test('should record evaluate under replay cache cap pressure', () {
      final evals = _evaluations();
      final cap = _replayCap();
      final iterations = _iterations();
      final fixedNow = DateTime.utc(2024, 6, 15, 12);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final guard = RpcRequestGuard(
            nowProvider: () => fixedNow,
            maxRequestsPerWindow: evals + 16,
            maxReplayCacheEntries: cap,
          );
          for (var i = 0; i < evals; i++) {
            final r = guard.evaluate(
              RpcRequest(
                jsonrpc: '2.0',
                method: 'bench',
                id: 'rid-$i',
              ),
            );
            expect(r, RpcRequestGuardResult.allow);
          }
        },
        iterations: iterations,
      );

      if (E2EEnv.get('RPC_REQUEST_GUARD_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('RPC_REQUEST_GUARD_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}rpc_request_guard.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'rpc_request_guard_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'evaluations_per_iteration': evals,
              'max_replay_cache_entries': cap,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'evaluate_replay_cap_pressure': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
