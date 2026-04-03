import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/benchmark_transport_pipeline.dart' as benchmark;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a reproducible transport benchmark report', () async {
    final report = await benchmark.buildTransportPipelineBenchmarkReport(
      iterations: 4,
      warmupIterations: 1,
    );

    stdout.writeln(report);

    expect(report, contains('# Transport Pipeline Benchmark'));
    expect(report, contains('small_sql_repetitive'));
    expect(report, contains('large_sql_low_compressibility'));
    expect(report, contains('large_incompressible_blob'));
    expect(report, contains('| async | auto |'));
    expect(report, contains('stage-p50/p95/p99 (ms)'));
  }, timeout: Timeout.none);
}
