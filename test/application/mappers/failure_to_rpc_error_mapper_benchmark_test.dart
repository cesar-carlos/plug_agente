@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw =
      E2EEnv.get('FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 256);
}

int _rounds() {
  final raw = E2EEnv.get('FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK_ROUNDS')
      ?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 10) {
    return 500;
  }
  return n.clamp(10, 100000);
}

List<Failure> _failureMix() {
  return <Failure>[
    ValidationFailure('validation'),
    ValidationFailure.withContext(
      message: 'sql validation',
      context: const {'operation': 'sql_validation'},
    ),
    QueryExecutionFailure.withContext(
      message: 'timeout',
      context: const {'timeout': true},
    ),
    QueryExecutionFailure.withContext(
      message: 'tx',
      context: const {'reason': 'transaction_failed'},
    ),
    DatabaseFailure.withContext(
      message: 'pool',
      context: const {'poolExhausted': true},
    ),
    NetworkFailure.withContext(
      message: 'net',
      context: const {'timeout': true},
    ),
    NetworkFailure.withContext(
      message: 'stage',
      context: const {'timeout': true, 'timeout_stage': 'transport'},
    ),
    ConfigurationFailure.withContext(
      message: 'auth',
      context: const {'authentication': true},
    ),
    PayloadEncodingFailure.withContext(
      message: 'decode',
      context: const {'operation': 'jsonDecode'},
    ),
    CompressionFailure.withContext(
      message: 'decompress',
      context: const {'operation': 'decompress'},
    ),
    ServerFailure('server'),
    NotFoundFailure('nf'),
  ];
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK') != 'true') {
    group('FailureToRpcErrorMapper benchmark', () {
      test(
        'skipped — set FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK=true to run',
        () {},
        skip:
            'Defina FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK=true para medir map().',
      );
    });
    return;
  }

  group('FailureToRpcErrorMapper benchmark', () {
    test('should record map() over mixed failure types', () {
      final rounds = _rounds();
      final iterations = _iterations();
      final failures = _failureMix();

      final stats = E2eBenchmarkStats.measureSync(
        () {
          for (var r = 0; r < rounds; r++) {
            final f = failures[r % failures.length];
            final err = FailureToRpcErrorMapper.map(
              f,
              useTimeoutByStage: true,
            );
            expect(err.code, isNot(0));
          }
        },
        iterations: iterations,
      );

      if (E2EEnv.get('FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK_RECORD') ==
          'true') {
        final custom = E2EEnv.get(
          'FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK_FILE',
        )?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}failure_to_rpc_error_mapper.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'failure_to_rpc_error_mapper_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'rounds_per_iteration': rounds,
              'failure_variants': failures.length,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'map_mixed_failures': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
