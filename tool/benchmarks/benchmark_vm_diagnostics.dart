import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<Map<String, Object?>> captureBenchmarkDiagnostics(
  Future<void> Function() workload, {
  Future<void> Function()? profileWorkload,
}) async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) throw StateError('Diagnostics require flutter test --enable-vmservice');
  final service = await vmServiceConnectUri(uri.replace(scheme: 'ws', path: '${uri.path}ws').toString());
  try {
    await workload();
    Future<Map<String, Object?>> checkpoint({required bool reset, bool recordAllocations = false}) async {
      var heap = 0;
      final allocations = <String, Object?>{};
      final groups = <String, IsolateRef>{};
      for (final isolate in (await service.getVM()).isolates ?? <IsolateRef>[]) {
        if (isolate.isSystemIsolate != true && isolate.isolateGroupId != null) {
          groups.putIfAbsent(isolate.isolateGroupId!, () => isolate);
        }
      }
      final memory = <String, Object?>{};
      for (final entry in groups.entries) {
        final isolate = entry.value;
        final id = isolate.id!;
        // Rich profiles retain thousands of maps. Keep them outside the heap
        // checkpoints so the observer's own report is not measured as growth.
        if (recordAllocations) {
          final allocation = await service.getAllocationProfile(id, gc: true, reset: reset);
          allocations[isolate.name ?? id] = allocation.toJson();
        } else {
          await service.getAllocationProfile(id, gc: true, reset: reset);
        }
        final usage = await service.getIsolateGroupMemoryUsage(entry.key);
        heap += usage.heapUsage!;
        memory[isolate.name ?? entry.key] = usage.toJson();
      }
      return {'heap_used_bytes': heap, 'memory_by_group': memory, 'allocations': allocations};
    }

    // Warm VM-service serialization before measuring the application heap.
    await checkpoint(reset: false);
    final before = await checkpoint(reset: true);
    await workload();
    final after = await checkpoint(reset: false);
    final retentionCycles = <Map<String, Object?>>[];
    for (var cycle = 0; cycle < 5; cycle++) {
      await workload();
      retentionCycles.add(await checkpoint(reset: false));
    }
    await checkpoint(reset: true);
    await service.setFlag('profiler', 'true');
    await service.setVMTimelineFlags(['GC', 'Dart', 'Embedder']);
    await service.clearVMTimeline();
    final start = (await service.getVMTimelineMicros()).timestamp!;
    await (profileWorkload ?? workload)();
    final end = (await service.getVMTimelineMicros()).timestamp!;
    final allocationProfile = await checkpoint(reset: false, recordAllocations: true);
    final cpu = <String, Object?>{};
    for (final isolate in (await service.getVM()).isolates ?? <IsolateRef>[]) {
      cpu[isolate.name ?? isolate.id!] = (await service.getCpuSamples(isolate.id!, start, end - start)).toJson();
    }
    final timeline = (await service.getVMTimeline()).toJson();
    return {
      'diagnostics_version': 2,
      'heap_growth_bytes': max(0, (after['heap_used_bytes']! as int) - (before['heap_used_bytes']! as int)),
      'rss_bytes': ProcessInfo.currentRss,
      'before': before,
      'after': after,
      'retention_cycles': retentionCycles,
      'allocation_profile': allocationProfile,
      'cpu_samples': cpu,
      'timeline': timeline,
      'elapsed_us': end - start,
    };
  } finally {
    await service.dispose();
  }
}
