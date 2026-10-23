import 'package:win32/win32.dart';
import 'package:windows_action_runtime/windows_action_runtime.dart';

/// Owns the action tree, never the elevated helper itself.
class ElevatedProcessJob {
  ElevatedProcessJob._(this._api, this._handle);
  final WindowsActionJobApi _api;
  final HANDLE _handle;
  bool _closed = false;

  static ElevatedProcessJob attach(
    int pid,
    int cpuLimitPercent, {
    WindowsActionJobApi? api,
  }) {
    if (cpuLimitPercent < 0 || cpuLimitPercent > 100) {
      throw const FormatException('CPU limit must be between 0 and 100.');
    }
    final native = api ?? WindowsActionJobApi();
    final created = native.create();
    if (created.value.isNull)
      throw StateError('Unable to create process job: ${created.error}');
    final job = ElevatedProcessJob._(native, created.value);
    try {
      _check(
        native.configure(created.value, 2 * 1024 * 1024 * 1024),
        'configure process memory limit',
      );
      if (cpuLimitPercent > 0) {
        _check(
          native.configureCpu(created.value, cpuLimitPercent),
          'apply CPU limit; check Windows session support or disable the limit in Actions preferences',
        );
      }
      final opened = native.open(pid);
      if (opened.value.isNull)
        throw StateError('Unable to open action process: ${opened.error}');
      try {
        _check(
          native.assign(created.value, opened.value),
          'assign process to job',
        );
      } finally {
        _check(native.close(opened.value), 'close action process handle');
      }
      return job;
    } on Object {
      job.close();
      rethrow;
    }
  }

  int readCpuMicroseconds() {
    if (_closed) throw StateError('Process job is closed.');
    final result = _api.cpuTicks(_handle);
    if (result.error != const WIN32_ERROR(0))
      throw StateError('Unable to read action CPU: ${result.error}');
    return result.value ~/ 10;
  }

  void terminate() =>
      _check(_api.terminate(_handle, 1), 'terminate action tree');

  void close() {
    if (_closed) return;
    _check(_api.close(_handle), 'close action job');
    _closed = true;
  }

  static void _check(Win32Result<bool> result, String operation) {
    if (!result.value)
      throw StateError('Unable to $operation: ${result.error}');
  }
}
