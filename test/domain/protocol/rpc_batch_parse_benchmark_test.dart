@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_batch.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('RPC_BATCH_PARSE_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _paramPad() {
  final raw = E2EEnv.get('RPC_BATCH_PARSE_BENCHMARK_PARAM_PAD')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 0) {
    return 2000;
  }
  return n.clamp(0, 500000);
}

List<dynamic> _buildBatchJson(int pad) {
  return List<dynamic>.generate(
    rpcBatchMaxSize,
    (int i) => <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'sql.execute',
      'id': i,
      'params': <String, dynamic>{
        'sql': 'SELECT 1',
        'bench_pad': 'x' * pad,
      },
    },
    growable: false,
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('RPC_BATCH_PARSE_BENCHMARK') != 'true') {
    group('RpcBatchRequest parse benchmark', () {
      test(
        'skipped — set RPC_BATCH_PARSE_BENCHMARK=true to run',
        () {},
        skip:
            'Defina RPC_BATCH_PARSE_BENCHMARK=true para medir fromJson/toJson.',
      );
    });
    return;
  }

  group('RpcBatchRequest parse benchmark', () {
    test('should record fromJson + validateStrict + toJson', () {
      final pad = _paramPad();
      final iterations = _iterations();
      final raw = _buildBatchJson(pad);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final batch = RpcBatchRequest.fromJson(raw);
          expect(batch.length, rpcBatchMaxSize);
          expect(batch.validateStrict(), isA<RpcBatchValid>());
          final round = batch.toJson();
          expect(round.length, rpcBatchMaxSize);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('RPC_BATCH_PARSE_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('RPC_BATCH_PARSE_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}rpc_batch_parse.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'rpc_batch_parse_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'batch_size': rpcBatchMaxSize,
              'param_pad_chars': pad,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'from_json_validate_to_json': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
