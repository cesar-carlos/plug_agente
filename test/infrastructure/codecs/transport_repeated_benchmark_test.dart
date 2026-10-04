import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../../tool/benchmarks/benchmark_transport_pipeline.dart' as benchmark;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'records nine identical transport profiles',
    () async {
      final report = await benchmark.buildRepeatedTransportBenchmark();
      final path =
          Platform.environment['AGENT_TRANSPORT_BENCH_OUTPUT'] ?? 'build/communication-transport-candidate.json';
      File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      expect(report['repetitions'], hasLength(9));
      final repetitions = report['repetitions'] as List<List<Map<String, dynamic>>>;
      expect(repetitions.first.any((row) => row['effective_compression'] == 'gzip'), isTrue);
      for (final rows in repetitions) {
        for (final row in rows) {
          expect(row['send_sample_count'], 100);
          expect(row['receive_sample_count'], 100);
        }
        expect(
          rows.map((row) => [row['case'], row['requested_compression'], row['signed']]).toList(),
          repetitions.first.map((row) => [row['case'], row['requested_compression'], row['signed']]).toList(),
        );
      }
    },
    timeout: Timeout.none,
    tags: const ['perf'],
  );
}
