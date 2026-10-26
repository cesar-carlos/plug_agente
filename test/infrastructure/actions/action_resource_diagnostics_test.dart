import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/action_resource_diagnostics.dart';

void main() {
  test('native process memory reports bytes and preserves unavailable measurements', () {
    final sample = ActionResourceDiagnostics.readActionProcessMemory(pid);
    expect(sample['action_main_process_rss_bytes'], greaterThan(0));
    expect(sample['action_main_process_commit_bytes'], greaterThan(0));
    final unavailable = ActionResourceDiagnostics.readActionProcessMemory(0);
    expect(unavailable, contains('action_main_process_memory_error'));
    expect(unavailable, isNot(contains('action_main_process_rss_bytes')));
  }, skip: !Platform.isWindows);

  test('separates agent and job CPU, normalizes cores and records visibility', () {
    var wall = 0;
    var cpu = 0;
    var visible = true;
    final tracker = ActionResourceDiagnostics(
      processors: 4,
      elapsedMicros: () => wall,
      renderingEnabled: () => visible,
      readAgent: () => {'agent_process_own_cpu_us': cpu, 'agent_process_commit_bytes': 100},
    );
    expect(tracker.sample(jobCpu: Duration.zero)['agent_process_cpu_percent'], isNull);
    wall = 1000000;
    cpu = 2000000;
    visible = false;
    final sample = tracker.sample(jobCpu: const Duration(milliseconds: 400));
    expect(sample['agent_process_cpu_percent'], 50);
    expect(sample['action_job_cpu_percent'], 10);
    expect(sample['agent_process_commit_bytes'], 100);
    expect(sample['ui_rendering_enabled'], isFalse);
  });

  test('missing samples and counter resets are unavailable, never zero CPU', () {
    var wall = 0;
    int? cpu = 100;
    final tracker = ActionResourceDiagnostics(
      processors: 1,
      elapsedMicros: () => wall,
      readAgent: () => {'agent_process_own_cpu_us': cpu},
    );
    tracker.sample(jobCpu: const Duration(seconds: 1));
    wall++;
    cpu = null;
    expect(tracker.sample()['agent_process_cpu_percent'], isNull);
    wall++;
    cpu = 10;
    final recovered = tracker.sample(jobCpu: Duration.zero);
    expect(recovered['agent_process_cpu_percent'], isNull);
    expect(recovered['action_job_cpu_percent'], isNull);
    wall++;
    cpu = 0;
    expect(tracker.sample()['agent_process_cpu_percent'], isNull);
  });
}
