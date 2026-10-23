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

  Win32Result<bool> configureCpu(HANDLE job, int percent) {
    final limits = calloc<ActionJobCpuLimits>();
    try {
      limits.ref.flags = 0x1 | 0x4;
      limits.ref.rate = percent * 100;
      return SetInformationJobObject(job, JobObjectCpuRateControlInformation, limits, sizeOf<ActionJobCpuLimits>());
    } finally {
      calloc.free(limits);
    }
  }

  Win32Result<int> cpuTicks(HANDLE job) {
    final accounting = calloc<ActionJobAccounting>();
    try {
      final result = QueryInformationJobObject(
        job,
        JobObjectBasicAccountingInformation,
        accounting,
        sizeOf<ActionJobAccounting>(),
        null,
      );
      return Win32Result(
        value: accounting.ref.kernelTime + accounting.ref.userTime,
        error: result.value ? const WIN32_ERROR(0) : result.error,
      );
    } finally {
      calloc.free(accounting);
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

final class ActionJobCpuLimits extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int rate;
}

final class ActionJobAccounting extends Struct {
  @Int64()
  external int userTime;
  @Int64()
  external int kernelTime;
  @Int64()
  external int periodUserTime;
  @Int64()
  external int periodKernelTime;
  @Uint32()
  external int pageFaults;
  @Uint32()
  external int totalProcesses;
  @Uint32()
  external int activeProcesses;
  @Uint32()
  external int terminatedProcesses;
}
