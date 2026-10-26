import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// One bounded sample per interval; never retains a history of measurements.
class ActionResourceDiagnostics {
  ActionResourceDiagnostics({
    this.renderingEnabled,
    Map<String, Object?> Function()? readAgent,
    int Function()? elapsedMicros,
    int? processors,
  }) : _readAgent = readAgent ?? readNativeAgentResources,
       _elapsedMicros = elapsedMicros,
       _processors = processors ?? Platform.numberOfProcessors;

  final bool? Function()? renderingEnabled;
  final Map<String, Object?> Function() _readAgent;
  final int Function()? _elapsedMicros;
  final int _processors;
  final Stopwatch _watch = Stopwatch()..start();
  ({int wall, int? agent, int? job})? _previous;

  Map<String, Object?> sample({Duration? jobCpu, int? actionPid}) {
    final agent = _readAgent();
    final now = (
      wall: _elapsedMicros?.call() ?? _watch.elapsedMicroseconds,
      agent: agent['agent_process_own_cpu_us'] as int?,
      job: jobCpu?.inMicroseconds,
    );
    final previous = _previous;
    _previous = now;
    double? percent(int? current, int? old) {
      if (previous == null || current == null || old == null || current < old || now.wall <= previous.wall) {
        return null;
      }
      return (100 * (current - old) / (now.wall - previous.wall) / _processors).clamp(0, 100);
    }

    return {
      ...agent,
      if (actionPid != null) ...readActionProcessMemory(actionPid),
      'logical_processors': _processors,
      'ui_rendering_enabled': renderingEnabled?.call(),
      'action_job_cpu_ms': jobCpu?.inMilliseconds,
      'agent_process_cpu_percent': percent(now.agent, previous?.agent),
      'action_job_cpu_percent': percent(now.job, previous?.job),
    };
  }

  // Main executable only; unlike job CPU these values do not sum descendants.
  static Map<String, Object?> readActionProcessMemory(int pid) {
    if (!Platform.isWindows) return {};
    final opened = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
    final handle = opened.value;
    if (!handle.isValid) return {'action_main_process_memory_error': opened.error.toInt()};
    final values = <String, Object?>{};
    try {
      using((arena) {
        final memory = arena<PROCESS_MEMORY_COUNTERS>();
        memory.ref.cb = sizeOf<PROCESS_MEMORY_COUNTERS>();
        final measured = GetProcessMemoryInfo(handle, memory, memory.ref.cb);
        if (measured.value) {
          values['action_main_process_rss_bytes'] = memory.ref.WorkingSetSize;
          values['action_main_process_commit_bytes'] = memory.ref.PagefileUsage;
        } else {
          values['action_main_process_memory_error'] = measured.error.toInt();
        }
      });
    } finally {
      final closed = CloseHandle(handle);
      if (!closed.value) values['action_main_process_close_error'] = closed.error.toInt();
    }
    return values;
  }

  static Map<String, Object?> readNativeAgentResources() {
    final values = <String, Object?>{
      'agent_process_current_rss_bytes': ProcessInfo.currentRss,
      'agent_process_max_rss_bytes': ProcessInfo.maxRss,
    };
    if (!Platform.isWindows) return values;
    return using((arena) {
      final memory = arena<PROCESS_MEMORY_COUNTERS>();
      memory.ref.cb = sizeOf<PROCESS_MEMORY_COUNTERS>();
      final measured = GetProcessMemoryInfo(GetCurrentProcess(), memory, memory.ref.cb);
      if (measured.value) {
        values['agent_process_commit_bytes'] = memory.ref.PagefileUsage;
      } else {
        values['agent_process_memory_error'] = measured.error.toInt();
      }
      final creation = arena<FILETIME>();
      final ended = arena<FILETIME>();
      final kernel = arena<FILETIME>();
      final user = arena<FILETIME>();
      final measuredCpu = GetProcessTimes(GetCurrentProcess(), creation, ended, kernel, user);
      if (measuredCpu.value) {
        int ticks(FILETIME value) => (value.dwHighDateTime << 32) | value.dwLowDateTime;
        final micros = (ticks(kernel.ref) + ticks(user.ref)) ~/ 10;
        values['agent_process_own_cpu_us'] = micros;
        values['agent_process_own_cpu_ms'] = micros ~/ 1000;
      } else {
        values['agent_process_cpu_error'] = measuredCpu.error.toInt();
      }
      return values;
    });
  }
}
