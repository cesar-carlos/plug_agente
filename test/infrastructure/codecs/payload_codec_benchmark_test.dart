@Tags(['benchmark'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('PAYLOAD_CODEC_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _listLength() {
  final raw = E2EEnv.get('PAYLOAD_CODEC_BENCHMARK_LIST_LEN')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 3000;
  }
  return n.clamp(1, 100000);
}

List<Map<String, dynamic>> _payload(int len) {
  return List<Map<String, dynamic>>.generate(
    len,
    (int i) => <String, dynamic>{'i': i, 't': 'x$i'},
    growable: false,
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('PAYLOAD_CODEC_BENCHMARK') != 'true') {
    group('JsonPayloadCodec benchmark', () {
      test(
        'skipped — set PAYLOAD_CODEC_BENCHMARK=true to run',
        () {},
        skip: 'Defina PAYLOAD_CODEC_BENCHMARK=true no .env para medir encode/decode.',
      );
    });
    return;
  }

  group('JsonPayloadCodec benchmark', () {
    test('should record JsonUtf8 encode+decode round-trip', () {
      final listLen = _listLength();
      final iterations = _iterations();
      final data = _payload(listLen);
      const codec = JsonPayloadCodec();

      Uint8List? cachedBytes;

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final enc = codec.encode(data);
          expect(enc.isSuccess(), isTrue);
          final bytes = enc.getOrThrow();
          final dec = codec.decode(bytes);
          expect(dec.isSuccess(), isTrue);
          cachedBytes = bytes;
        },
        iterations: iterations,
      );

      expect(cachedBytes, isNotNull);

      if (E2EEnv.get('PAYLOAD_CODEC_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('PAYLOAD_CODEC_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}payload_codec.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'payload_codec_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'list_len': listLen,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'json_utf8_encode_decode_roundtrip': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
