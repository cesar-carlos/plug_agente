@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

int _iterations() {
  final raw = E2EEnv.get('POLICY_DECODE_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _payloadPad() {
  final raw = E2EEnv.get('POLICY_DECODE_BENCHMARK_PAYLOAD_PAD')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 0) {
    return 8000;
  }
  return n.clamp(0, 512 * 1024);
}

String _buildToken(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$encodedPayload.sig';
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('POLICY_DECODE_BENCHMARK') != 'true') {
    group('AuthorizationPolicyResolver decode benchmark', () {
      test(
        'skipped — set POLICY_DECODE_BENCHMARK=true to run',
        () {},
        skip:
            'Defina POLICY_DECODE_BENCHMARK=true para medir decode-only resolvePolicy.',
      );
    });
    return;
  }

  group('AuthorizationPolicyResolver decode benchmark', () {
    test('should record resolvePolicy decode-only path', () async {
      final pad = _payloadPad();
      final iterations = _iterations();
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': 'bench-client',
          'all_tables': true,
          'all_views': false,
          'all_permissions': true,
          'rules': const <Map<String, dynamic>>[],
          'bench_pad': 'p' * pad,
        },
      });

      final flags = MockFeatureFlags();
      when(() => flags.enableSocketJwksValidation).thenReturn(false);
      when(() => flags.enableSocketRevokedTokenInSession).thenReturn(false);
      final resolver = AuthorizationPolicyResolver(flags);

      final stats = await E2eBenchmarkStats.measureAsync(
        () async {
          final result = await resolver.resolvePolicy(token);
          expect(result.isSuccess(), isTrue);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('POLICY_DECODE_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('POLICY_DECODE_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}policy_decode.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'policy_decode_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'payload_pad_chars': pad,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'resolve_policy_decode_only': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
