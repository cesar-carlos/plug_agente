@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('RETRY_MANAGER_BENCHMARK') != 'true') {
    group('RetryManager benchmark', () {
      test(
        'skipped — set RETRY_MANAGER_BENCHMARK=true to run',
        () {},
        skip:
            'Defina RETRY_MANAGER_BENCHMARK=true no .env para medir backoff sintetico.',
      );
    });
    return;
  }

  group('RetryManager benchmark', () {
    test('should record latency for transient failures with short backoff', () async {
      final retry = RetryManager();
      var attempts = 0;
      final stats = await E2eBenchmarkStats.measureAsync(
        () async {
          attempts = 0;
          final result = await retry.execute<String>(
            () async {
              attempts++;
              if (attempts < 3) {
                return Failure(
                  domain.ConnectionFailure.withContext(
                    message: 'synthetic connection timeout for benchmark',
                  ),
                );
              }
              return const Success('ok');
            },
            initialDelayMs: 2,
          );
          expect(result.isSuccess(), isTrue);
          expect(attempts, 3);
        },
        warmup: 1,
      );

      if (E2EEnv.get('RETRY_MANAGER_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('RETRY_MANAGER_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}retry_manager.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 2,
            'suite': 'retry_manager_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'cases': <String, dynamic>{
              'retry_transient_2_delays': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
