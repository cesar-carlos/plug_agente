import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/benchmarks/benchmark_transport_pipeline.dart';
import '../../../tool/benchmarks/benchmark_vm_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'captures transport heap, CPU, allocations and GC outside qualification timing',
    () async {
      final report = await captureBenchmarkDiagnostics(
        () async {
          await buildTransportPipelineBenchmarkReport(iterations: 100, warmupIterations: 10);
        },
        profileWorkload: runTransportDiagnosticsWorkload,
      );
      report['heap_workload'] = 'all_transport_profiles_100_iterations_v2';
      report['cpu_workload'] = 'large_sql_low_compressibility_100_iterations_v2';
      final path = Platform.environment['AGENT_TRANSPORT_DIAGNOSTICS_OUTPUT'] ?? 'build/transport-diagnostics.json';
      File(path).writeAsStringSync(jsonEncode(report));
      expect(report['heap_growth_bytes'], isNonNegative);
      expect(report['cpu_samples'], isNotEmpty);
    },
    timeout: Timeout.none,
    tags: const ['perf'],
  );
}
