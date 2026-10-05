import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/benchmark_vm_diagnostics.dart';

/// Run explicitly with --enable-vmservice; excluded from ordinary unit suites.
void main() {
  test('heap checkpoints do not retain their allocation reports', () async {
    var workloads = 0;
    var profiles = 0;
    final report = await captureBenchmarkDiagnostics(
      () async {
        workloads++;
        await Future<void>.delayed(Duration.zero);
      },
      profileWorkload: () async {
        profiles++;
        await Future<void>.delayed(Duration.zero);
      },
    );
    expect(report['diagnostics_version'], 2);
    expect(report['heap_growth_bytes'], isNonNegative);
    expect(workloads, 7);
    expect(profiles, 1);
    final checkpoints = [
      report['before']! as Map<String, Object?>,
      report['after']! as Map<String, Object?>,
      ...report['retention_cycles']! as List<Map<String, Object?>>,
    ];
    expect(checkpoints, hasLength(7));
    for (final checkpoint in checkpoints) {
      expect(checkpoint['allocations'], isEmpty);
      expect(checkpoint['heap_used_bytes'], greaterThan(0));
      expect(checkpoint['memory_by_group'], isNotEmpty);
    }
    final profile = report['allocation_profile']! as Map<String, Object?>;
    expect(profile['allocations'], isNotEmpty);
  }, tags: const ['perf']);
}
