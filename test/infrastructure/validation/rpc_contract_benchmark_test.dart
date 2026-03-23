@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('RPC_CONTRACT_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _rowCount() {
  final raw = E2EEnv.get('RPC_CONTRACT_BENCHMARK_RESULT_ROWS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 2000;
  }
  return n.clamp(1, 100000);
}

Map<String, dynamic> _responseWithRows(int rows) {
  final rowMaps = List<Map<String, dynamic>>.generate(
    rows,
    (int i) => <String, dynamic>{'id': i, 'label': 'r$i'},
    growable: false,
  );
  return <String, dynamic>{
    'jsonrpc': '2.0',
    'id': 1,
    'result': <String, dynamic>{
      'execution_id': 'exec-bench',
      'started_at': '2020-01-01T00:00:00.000Z',
      'finished_at': '2020-01-01T00:00:01.000Z',
      'rows': rowMaps,
      'row_count': rows,
    },
  };
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('RPC_CONTRACT_BENCHMARK') != 'true') {
    group('RpcContractValidator benchmark', () {
      test(
        'skipped — set RPC_CONTRACT_BENCHMARK=true to run',
        () {},
        skip:
            'Defina RPC_CONTRACT_BENCHMARK=true no .env para medir validateResponse.',
      );
    });
    return;
  }

  group('RpcContractValidator benchmark', () {
    test('should record validateResponse for large sql result object', () {
      final rowCount = _rowCount();
      final iterations = _iterations();
      final payload = _responseWithRows(rowCount);
      const validator = RpcContractValidator();

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final result = validator.validateResponse(payload);
          expect(result.isSuccess(), isTrue);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('RPC_CONTRACT_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('RPC_CONTRACT_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}rpc_contract.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'rpc_contract_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'result_rows': rowCount,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'validate_response_large_result': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
