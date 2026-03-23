@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('CLIENT_TOKEN_HASH_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 24;
  }
  return n.clamp(3, 512);
}

int _tokenChars() {
  final raw = E2EEnv.get('CLIENT_TOKEN_HASH_BENCHMARK_TOKEN_CHARS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 8) {
    return 4096;
  }
  return n.clamp(8, 2 * 1024 * 1024);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('CLIENT_TOKEN_HASH_BENCHMARK') != 'true') {
    group('client token hash benchmark', () {
      test(
        'skipped — set CLIENT_TOKEN_HASH_BENCHMARK=true to run',
        () {},
        skip:
            'Defina CLIENT_TOKEN_HASH_BENCHMARK=true para medir hashClientCredentialToken.',
      );
    });
    return;
  }

  group('client token hash benchmark', () {
    test('should record normalize + sha256 hex', () {
      final chars = _tokenChars();
      final iterations = _iterations();
      final token = 'Bearer ${'t' * chars}';

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final h = hashClientCredentialToken(token);
          expect(h, hasLength(64));
          expect(normalizeClientCredentialToken(token), isNotEmpty);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('CLIENT_TOKEN_HASH_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('CLIENT_TOKEN_HASH_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}client_token_hash.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'client_token_hash_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'credential_chars': chars,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'hash_client_credential_token': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
