@Tags(['benchmark'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/compression_codec.dart';

/// Micro-benchmark for shared GZIP primitives (`gzipCompressBytesOrThrow` /
/// `gzipDecompressBytesOrThrow`).
///
/// Run:
/// `CODEC_GZIP_BENCHMARK=true flutter test test/benchmark/gzip_codec_benchmark_test.dart --tags benchmark`
///
/// Optional: `CODEC_GZIP_BENCHMARK_ITERATIONS=40` (default 24),
/// `CODEC_GZIP_BENCHMARK_PAYLOAD_KB=512` (default 256).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runBenchmark = Platform.environment['CODEC_GZIP_BENCHMARK'] == 'true';

  group('GZIP codec benchmark', () {
    test(
      'measures compress+decompress throughput on repetitive payload',
      () {
        final iterations =
            int.tryParse(
              Platform.environment['CODEC_GZIP_BENCHMARK_ITERATIONS'] ?? '',
            ) ??
            24;
        expect(iterations, greaterThan(0));

        final payloadSizeKb =
            int.tryParse(
              Platform.environment['CODEC_GZIP_BENCHMARK_PAYLOAD_KB'] ?? '',
            ) ??
            256;
        expect(payloadSizeKb, greaterThan(0));

        final data = Uint8List(payloadSizeKb * 1024);
        for (var i = 0; i < data.length; i++) {
          data[i] = (i % 251) + 1;
        }

        final wall = Stopwatch()..start();
        var lastCompressed = gzipCompressBytesOrThrow(data);
        for (var i = 1; i < iterations; i++) {
          lastCompressed = gzipCompressBytesOrThrow(data);
        }
        for (var i = 0; i < iterations; i++) {
          final round = gzipDecompressBytesOrThrow(lastCompressed);
          expect(round.length, equals(data.length));
        }
        wall.stop();

        // ignore: avoid_print
        print(
          'CODEC_GZIP_BENCHMARK iterations=$iterations payload_kb=$payloadSizeKb '
          'wall_ms=${wall.elapsedMilliseconds} '
          '(compress $iterations×, decompress $iterations×)',
        );

        expect(wall.elapsedMilliseconds, greaterThan(0));
      },
      skip: runBenchmark
          ? false
          : 'Set CODEC_GZIP_BENCHMARK=true to measure gzip primitive throughput.',
    );
  });
}
