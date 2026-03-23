@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('RPC_REQUEST_SCHEMA_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _batchSize() {
  final raw = E2EEnv.get('RPC_REQUEST_SCHEMA_BENCHMARK_BATCH_SIZE')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 32;
  }
  return n.clamp(1, 512);
}

List<Map<String, dynamic>> _buildBatch(int size) {
  return List<Map<String, dynamic>>.generate(
    size,
    (int i) => <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'sql.execute',
      'id': i,
      'params': <String, dynamic>{'sql': 'SELECT 1'},
    },
    growable: false,
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('RPC_REQUEST_SCHEMA_BENCHMARK') != 'true') {
    group('RpcRequestSchemaValidator benchmark', () {
      test(
        'skipped — set RPC_REQUEST_SCHEMA_BENCHMARK=true to run',
        () {},
        skip:
            'Defina RPC_REQUEST_SCHEMA_BENCHMARK=true no .env para medir validateBatch.',
      );
    });
    return;
  }

  group('RpcRequestSchemaValidator benchmark', () {
    test('should record validateBatch wall time for sql.execute items', () {
      final batchSize = _batchSize();
      final iterations = _iterations();
      final batch = _buildBatch(batchSize);
      const validator = RpcRequestSchemaValidator();
      final limits = TransportLimits(maxBatchSize: batchSize);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final result = validator.validateBatch(batch, limits: limits);
          expect(result.isSuccess(), isTrue);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('RPC_REQUEST_SCHEMA_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('RPC_REQUEST_SCHEMA_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}rpc_request_schema.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'rpc_request_schema_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'batch_size': batchSize,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'validate_batch_sql_execute': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
