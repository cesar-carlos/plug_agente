@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/compression/compression.dart';

/// Benchmark for `GzipCompressor` (JSON rows → gzip → base64 map), including
/// sync vs `compute` paths and `gzipRowComputeMinUtf8Bytes`.
///
/// Run:
/// `GZIP_COMPRESSOR_BENCHMARK=true flutter test test/benchmark/gzip_compressor_benchmark_test.dart --tags benchmark`
///
/// Optional:
/// - `GZIP_COMPRESSOR_BENCHMARK_ITERATIONS` (default 10)
/// - `GZIP_COMPRESSOR_BENCHMARK_SMALL_ROWS` (default 24)
/// - `GZIP_COMPRESSOR_BENCHMARK_LARGE_ROWS` (default 400)
/// - `GZIP_COMPRESSOR_BENCHMARK_LARGE_ROW_PAYLOAD_CHARS` (default 48)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runBenchmark = Platform.environment['GZIP_COMPRESSOR_BENCHMARK'] == 'true';

  group('GzipCompressor benchmark', () {
    test(
      'measures row compress+decompress (below and above UTF-8 threshold)',
      () async {
        final iterations = int.tryParse(
              Platform.environment['GZIP_COMPRESSOR_BENCHMARK_ITERATIONS'] ?? '',
            ) ??
            10;
        expect(iterations, greaterThan(0));

        final smallRowCount = int.tryParse(
              Platform.environment['GZIP_COMPRESSOR_BENCHMARK_SMALL_ROWS'] ?? '',
            ) ??
            24;
        expect(smallRowCount, greaterThan(0));

        final largeRowCount = int.tryParse(
              Platform.environment['GZIP_COMPRESSOR_BENCHMARK_LARGE_ROWS'] ?? '',
            ) ??
            400;
        expect(largeRowCount, greaterThan(0));

        final largeRowPayloadChars = int.tryParse(
              Platform.environment['GZIP_COMPRESSOR_BENCHMARK_LARGE_ROW_PAYLOAD_CHARS'] ??
                  '',
            ) ??
            48;
        expect(largeRowPayloadChars, greaterThan(0));

        final compressor = GzipCompressor();

        final smallRows = _buildSmallRows(smallRowCount);
        final largeRows = _buildLargeRows(largeRowCount, largeRowPayloadChars);

        final smallUtf8 = utf8.encode(jsonEncode(smallRows)).length;
        final largeUtf8 = utf8.encode(jsonEncode(largeRows)).length;
        expect(
          smallUtf8,
          lessThanOrEqualTo(gzipRowComputeMinUtf8Bytes),
          reason: 'Tune GZIP_COMPRESSOR_BENCHMARK_SMALL_ROWS so small case stays sync',
        );
        expect(
          largeUtf8,
          greaterThan(gzipRowComputeMinUtf8Bytes),
          reason: 'Tune GZIP_COMPRESSOR_BENCHMARK_LARGE_ROWS so large case uses compute',
        );

        Future<void> runCase(String label, List<Map<String, dynamic>> rows) async {
          final wall = Stopwatch()..start();
          for (var i = 0; i < iterations; i++) {
            final compressed = await compressor.compress(rows);
            expect(compressed.isSuccess(), isTrue, reason: label);
            final decompressed = await compressor.decompress(compressed.getOrThrow());
            expect(decompressed.isSuccess(), isTrue, reason: label);
            expect(decompressed.getOrThrow(), equals(rows), reason: label);
          }
          wall.stop();
          // ignore: avoid_print
          print(
            'GZIP_COMPRESSOR_BENCHMARK case=$label iterations=$iterations '
            'utf8_json_bytes=${utf8.encode(jsonEncode(rows)).length} '
            'wall_ms=${wall.elapsedMilliseconds}',
          );
          expect(wall.elapsedMilliseconds, greaterThan(0));
        }

        await runCase('small_sync_path', smallRows);
        await runCase('large_compute_path', largeRows);
      },
      skip: runBenchmark
          ? false
          : 'Set GZIP_COMPRESSOR_BENCHMARK=true to measure GzipCompressor throughput.',
    );
  });
}

List<Map<String, dynamic>> _buildSmallRows(int count) {
  return List<Map<String, dynamic>>.generate(
    count,
    (int i) => <String, dynamic>{'id': i, 'c': 's$i'},
  );
}

List<Map<String, dynamic>> _buildLargeRows(int count, int payloadChars) {
  final pad = 'p' * payloadChars;
  return List<Map<String, dynamic>>.generate(
    count,
    (int i) => <String, dynamic>{
      'id': i,
      'code': 'code_$i',
      'payload': '$pad$i',
    },
  );
}
