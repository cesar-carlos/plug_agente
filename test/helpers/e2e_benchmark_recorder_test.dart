import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e_benchmark_recorder.dart';

void main() {
  group('E2eBenchmarkStats', () {
    test('should summarize samples', () {
      const s = E2eBenchmarkStats(
        warmup: 1,
        iterations: 4,
        samplesMs: <int>[10, 20, 30, 40],
      );
      check(s.meanMs).equals(25);
      check(s.minMs).equals(10);
      check(s.maxMs).equals(40);
      check(s.medianMs).equals(25);
      check(s.p90Ms).equals(40);
      check(s.trimmedMeanMs).equals(25);
    });

    test('toJson should include p90 and trimmed_mean', () {
      const s = E2eBenchmarkStats(
        warmup: 0,
        iterations: 2,
        samplesMs: <int>[100, 200],
      );
      final j = s.toJson();
      check(j).containsKey('p90_ms');
      check(j).containsKey('trimmed_mean_ms');
    });

    test('p90Ms should use single sample', () {
      const s = E2eBenchmarkStats(
        warmup: 0,
        iterations: 1,
        samplesMs: <int>[77],
      );
      check(s.p90Ms).equals(77);
    });

    test('p95Ms should track high tail', () {
      const s = E2eBenchmarkStats(
        warmup: 0,
        iterations: 3,
        samplesMs: <int>[10, 20, 100],
      );
      check(s.p95Ms).equals(100);
    });

    test('toJson should include p95_ms', () {
      const s = E2eBenchmarkStats(
        warmup: 0,
        iterations: 1,
        samplesMs: <int>[5],
      );
      check(s.toJson()).containsKey('p95_ms');
    });

    test('trimmedMeanMs should match meanMs when fewer than 3 samples', () {
      const s = E2eBenchmarkStats(
        warmup: 0,
        iterations: 2,
        samplesMs: <int>[10, 30],
      );
      check(s.trimmedMeanMs).equals(s.meanMs);
    });

    test('trimmedMeanMs should drop min and max with 3+ samples', () {
      const s = E2eBenchmarkStats(
        warmup: 0,
        iterations: 5,
        samplesMs: <int>[1, 10, 20, 30, 100],
      );
      check(s.trimmedMeanMs).equals(20);
    });
  });

  test('appendE2eBenchmarkRecord should append valid JSON lines', () async {
    final dir = await Directory.systemTemp.createTemp('e2e_bench_');
    final file = File('${dir.path}/history.jsonl');
    appendE2eBenchmarkRecord(
      file: file,
      record: <String, dynamic>{'k': 1, 'suite': 'a'},
    );
    appendE2eBenchmarkRecord(
      file: file,
      record: <String, dynamic>{'k': 2, 'suite': 'b'},
    );
    final lines = await file.readAsLines();
    check(lines.length).equals(2);
    check(jsonDecode(lines[0]) as Map).containsKey('k');
    check((jsonDecode(lines[0]) as Map)['k']).equals(1);
    check((jsonDecode(lines[1]) as Map)['k']).equals(2);
    await dir.delete(recursive: true);
  });

  test(
    'resolveE2eBenchmarkOutputFile should join relative paths to project root',
    () {
      final root = resolveE2eProjectRoot();
      check(root).isNotNull();
      final f = resolveE2eBenchmarkOutputFile(
        'benchmark/e2e_odbc_rpc.jsonl',
      );
      check(f.path.endsWith('e2e_odbc_rpc.jsonl')).isTrue();
    },
  );
}
