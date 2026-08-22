import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

typedef WindowsProcessOpenChecker = int Function(int pid);
typedef WindowsProcessRunningPredicate = Future<bool> Function(int pid);

/// Best-effort check whether a Windows process id is still running.
class WindowsProcessLifetimeChecker {
  WindowsProcessLifetimeChecker({
    WindowsProcessOpenChecker? openProcessForPid,
    bool Function()? isWindows,
    WindowsProcessRunningPredicate? processRunningPredicate,
  }) : _openProcessForPid = openProcessForPid ?? _defaultOpenProcessForPid,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _processRunningPredicate = processRunningPredicate;

  static const String _logName = 'windows_process_lifetime_checker';

  final WindowsProcessOpenChecker _openProcessForPid;
  final bool Function() _isWindows;
  final WindowsProcessRunningPredicate? _processRunningPredicate;

  static int _defaultOpenProcessForPid(int pid) {
    final opened = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
    if (!opened.value.isValid) {
      return 0;
    }
    return opened.value.address;
  }

  Future<bool> isProcessRunning(int pid) async {
    final predicate = _processRunningPredicate;
    if (predicate != null) {
      return predicate(pid);
    }

    if (!_isWindows() || pid <= 0) {
      return false;
    }

    final handle = HANDLE(Pointer.fromAddress(_openProcessForPid(pid)));
    if (!handle.isValid) {
      final errorCode = GetLastError();
      if (errorCode == ERROR_INVALID_PARAMETER || errorCode == ERROR_ACCESS_DENIED) {
        return false;
      }

      developer.log(
        'Unable to open process handle for lifetime check; assuming process is running',
        name: _logName,
        level: 900,
        error: 'pid=$pid os_error_code=$errorCode',
      );
      return true;
    }

    final exitCode = calloc<Uint32>();
    try {
      final ok = GetExitCodeProcess(handle, exitCode);
      if (!ok.value) {
        developer.log(
          'GetExitCodeProcess failed; assuming process is running',
          name: _logName,
          level: 900,
          error: 'pid=$pid os_error_code=${GetLastError()}',
        );
        return true;
      }
      return exitCode.value == STILL_ACTIVE;
    } finally {
      calloc.free(exitCode);
      CloseHandle(handle);
    }
  }
}
