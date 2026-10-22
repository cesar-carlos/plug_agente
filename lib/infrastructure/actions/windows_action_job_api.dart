import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Native boundary for job limits and process ownership.
class WindowsActionJobApi {
  Win32Result<HANDLE> create() => CreateJobObject(null, null);

  Win32Result<bool> configure(HANDLE job, int memoryLimitBytes) {
    final limits = calloc<ActionJobExtendedLimits>();
    try {
      limits.ref.basic.flags = jobMemoryLimit | killOnJobClose;
      limits.ref.jobMemory = memoryLimitBytes;
      return SetInformationJobObject(job, JobObjectExtendedLimitInformation, limits, sizeOf<ActionJobExtendedLimits>());
    } finally {
      calloc.free(limits);
    }
  }

  Win32Result<HANDLE> open(int pid) => OpenProcess(PROCESS_TERMINATE | PROCESS_SET_QUOTA, false, pid);
  Win32Result<bool> assign(HANDLE job, HANDLE process) => AssignProcessToJobObject(job, process);
  Win32Result<bool> terminate(HANDLE job, int exitCode) => TerminateJobObject(job, exitCode);
  Win32Result<bool> close(HANDLE handle) => CloseHandle(handle);

  static const int jobMemoryLimit = 0x00000200;
  static const int killOnJobClose = 0x00002000;
}

// winnt.h JOBOBJECT_BASIC_LIMIT_INFORMATION / JOBOBJECT_EXTENDED_LIMIT_INFORMATION.
// These structures are not exposed by the pinned win32 package.
final class ActionJobBasicLimits extends Struct {
  @Int64()
  external int processTime;
  @Int64()
  external int jobTime;
  @Uint32()
  external int flags;
  @UintPtr()
  external int minimumWorkingSet;
  @UintPtr()
  external int maximumWorkingSet;
  @Uint32()
  external int activeProcesses;
  @UintPtr()
  external int affinity;
  @Uint32()
  external int priority;
  @Uint32()
  external int scheduling;
}

final class ActionJobExtendedLimits extends Struct {
  external ActionJobBasicLimits basic;
  @Array(6)
  external Array<Uint64> ioCounters;
  @UintPtr()
  external int processMemory;
  @UintPtr()
  external int jobMemory;
  @UintPtr()
  external int peakProcessMemory;
  @UintPtr()
  external int peakJobMemory;
}
