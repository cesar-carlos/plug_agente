@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_stream.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('STREAM_CHUNK_SERIALIZE_BENCHMARK_ITERATIONS')
      ?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _rowsPerChunk() {
  final raw = E2EEnv.get('STREAM_CHUNK_SERIALIZE_BENCHMARK_ROWS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 1500;
  }
  return n.clamp(1, 50000);
}

RpcStreamChunk _chunk(int rows) {
  final rowMaps = List<Map<String, dynamic>>.generate(
    rows,
    (int i) => <String, dynamic>{'a': i, 'b': 's$i'},
    growable: false,
  );
  return RpcStreamChunk(
    streamId: 'stream-bench',
    requestId: 1,
    chunkIndex: 0,
    rows: rowMaps,
    columnMetadata: [
      <String, dynamic>{'name': 'a', 'type': 'int'},
      <String, dynamic>{'name': 'b', 'type': 'string'},
    ],
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('STREAM_CHUNK_SERIALIZE_BENCHMARK') != 'true') {
    group('RpcStreamChunk serialize benchmark', () {
      test(
        'skipped — set STREAM_CHUNK_SERIALIZE_BENCHMARK=true to run',
        () {},
        skip:
            'Defina STREAM_CHUNK_SERIALIZE_BENCHMARK=true para medir toJson/jsonEncode.',
      );
    });
    return;
  }

  group('RpcStreamChunk serialize benchmark', () {
    test('should record toJson + jsonEncode wall time', () {
      final rowCount = _rowsPerChunk();
      final iterations = _iterations();
      final chunk = _chunk(rowCount);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final map = chunk.toJson();
          final wire = jsonEncode(map);
          expect(wire.length, greaterThan(rowCount));
        },
        iterations: iterations,
      );

      if (E2EEnv.get('STREAM_CHUNK_SERIALIZE_BENCHMARK_RECORD') == 'true') {
        final custom =
            E2EEnv.get('STREAM_CHUNK_SERIALIZE_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}stream_chunk_serialize.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'stream_chunk_serialize_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'rows_per_chunk': rowCount,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'rpc_stream_chunk_to_json_encode': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
