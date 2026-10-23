import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_command_line_quoter.dart';

const _inheritedHandleListAttribute = 0x00020002;

/// Starts suspended with NUL stdin and optional bounded native output readers.
/// Pipe draining happens outside the main isolate; disabled captures use NUL.
final class WindowsSilentActionProcess implements Process {
  WindowsSilentActionProcess._(this.pid, this._handle, this._thread) {
    _exit = _waitAndClose();
    unawaited(_exit.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool startSuspended = false,
    int captureStdoutBytes = 0,
    int captureStderrBytes = 0,
  }) async {
    if (executable.isEmpty || [executable, ...arguments, ?workingDirectory].any((value) => value.contains('\u0000'))) {
      throw ProcessException(executable, const [], 'Invalid process invocation');
    }
    final spawned = await Isolate.run(
      () => _spawn(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        captureStdout: captureStdoutBytes > 0,
        captureStderr: captureStderrBytes > 0,
      ),
    );
    final process = WindowsSilentActionProcess._(
      spawned.pid,
      HANDLE(Pointer.fromAddress(spawned.handle)),
      HANDLE(Pointer.fromAddress(spawned.thread)),
    );
    process._stdout = _output(spawned.stdoutRead, captureStdoutBytes);
    process._stderr = _output(spawned.stderrRead, captureStderrBytes);
    if (!startSuspended) {
      try {
        process.resume();
      } on Object {
        process.kill();
        rethrow;
      }
    }
    return process;
  }

  static ({int pid, int handle, int thread, int stdoutRead, int stderrRead}) _spawn(
    String executable,
    List<String> arguments, {
    required bool includeParentEnvironment,
    required bool captureStdout,
    required bool captureStderr,
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return using((arena) {
      final security = arena<SECURITY_ATTRIBUTES>();
      security.ref.nLength = sizeOf<SECURITY_ATTRIBUTES>();
      security.ref.bInheritHandle = true;
      final opened = CreateFile(
        PCWSTR('NUL'.toNativeUtf16(allocator: arena).cast()),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        security,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        null,
      );
      if (opened.value == INVALID_HANDLE_VALUE) {
        throw ProcessException(executable, const [], 'Unable to open null device', opened.error.toInt());
      }
      final device = opened.value;
      HANDLE? outputRead;
      HANDLE? outputWrite;
      HANDLE? errorRead;
      HANDLE? errorWrite;
      LPPROC_THREAD_ATTRIBUTE_LIST? attributes;
      var initialized = false;
      ({HANDLE process, HANDLE thread})? launched;
      try {
        if (captureStdout) {
          final pipe = _createPipe(security, arena);
          outputRead = pipe.read;
          outputWrite = pipe.write;
        }
        if (captureStderr) {
          final pipe = _createPipe(security, arena);
          errorRead = pipe.read;
          errorWrite = pipe.write;
        }
        final size = arena<IntPtr>();
        InitializeProcThreadAttributeList(null, 1, size);
        attributes = LPPROC_THREAD_ATTRIBUTE_LIST(arena<Uint8>(size.value).cast());
        final initializedResult = InitializeProcThreadAttributeList(attributes, 1, size);
        if (!initializedResult.value) {
          throw ProcessException(
            executable,
            const [],
            'Unable to initialize inherited handles',
            initializedResult.error.toInt(),
          );
        }
        initialized = true;
        final inherited = [device, ?outputWrite, ?errorWrite];
        final handles = arena<Pointer>(inherited.length);
        for (var index = 0; index < inherited.length; index++) {
          handles[index] = inherited[index];
        }
        final updated = UpdateProcThreadAttribute(
          attributes,
          0,
          _inheritedHandleListAttribute,
          handles,
          sizeOf<Pointer>() * inherited.length,
          null,
          null,
        );
        if (!updated.value) {
          throw ProcessException(executable, const [], 'Unable to restrict inherited handles', updated.error.toInt());
        }
        final startup = arena<STARTUPINFOEX>();
        startup.ref.lpAttributeList = attributes;
        startup.ref.StartupInfo.cb = sizeOf<STARTUPINFOEX>();
        startup.ref.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
        startup.ref.StartupInfo.hStdInput = device;
        startup.ref.StartupInfo.hStdOutput = outputWrite ?? device;
        startup.ref.StartupInfo.hStdError = errorWrite ?? device;
        final info = arena<PROCESS_INFORMATION>();
        final effectiveEnvironment = <String, String>{};
        for (final entry in {
          ...(includeParentEnvironment ? Platform.environment : <String, String>{}),
          ...?environment,
        }.entries) {
          if (entry.key.contains('\u0000') || entry.value.contains('\u0000') || entry.key.contains('=')) {
            throw ProcessException(executable, const [], 'Invalid process environment');
          }
          effectiveEnvironment.removeWhere((key, _) => key.toUpperCase() == entry.key.toUpperCase());
          effectiveEnvironment[entry.key] = entry.value;
        }
        final keys = effectiveEnvironment.keys.toList()..sort((a, b) => a.toUpperCase().compareTo(b.toUpperCase()));
        final block = '${keys.map((key) => '$key=${effectiveEnvironment[key]}').join('\u0000')}\u0000\u0000';
        final created = CreateProcess(
          null,
          PWSTR(
            _commandLine(executable, arguments).toNativeUtf16(allocator: arena).cast(),
          ),
          null,
          null,
          true,
          EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW | CREATE_SUSPENDED,
          block.toNativeUtf16(allocator: arena),
          workingDirectory == null ? null : PCWSTR(workingDirectory.toNativeUtf16(allocator: arena).cast()),
          startup.cast(),
          info,
        );
        if (!created.value) {
          throw ProcessException(executable, const [], 'Unable to start silent action process', created.error.toInt());
        }
        launched = (process: info.ref.hProcess, thread: info.ref.hThread);
        return (
          pid: info.ref.dwProcessId,
          handle: info.ref.hProcess.address,
          thread: info.ref.hThread.address,
          stdoutRead: outputRead?.address ?? 0,
          stderrRead: errorRead?.address ?? 0,
        );
      } finally {
        if (initialized) DeleteProcThreadAttributeList(attributes!);
        try {
          if (outputWrite != null) _closeDevice(outputWrite, launched);
          if (errorWrite != null) _closeDevice(errorWrite, launched);
        } finally {
          if (launched == null) {
            if (outputRead != null) _closeHandle(outputRead);
            if (errorRead != null) _closeHandle(errorRead);
          }
          _closeDevice(device, launched);
        }
      }
    });
  }

  @override
  final int pid;
  final HANDLE _handle;
  HANDLE? _thread;
  bool _closed = false;
  late final Future<int> _exit;
  @override
  Future<int> get exitCode => _exit;
  @override
  Stream<List<int>> get stdout => _stdout;
  Stream<List<int>> _stdout = const Stream.empty();
  @override
  Stream<List<int>> get stderr => _stderr;
  Stream<List<int>> _stderr = const Stream.empty();
  @override
  late final IOSink stdin = IOSink(_ClosedInput());

  Future<int> _waitAndClose() async {
    final address = _handle.address;
    try {
      return await Isolate.run(() => _waitForExit(address));
    } finally {
      _closed = true;
      try {
        _closeThread();
      } finally {
        _closeHandle(_handle);
      }
    }
  }

  /// Resume only after the caller has attached the suspended process to its job.
  void resume() {
    final thread = _thread;
    if (thread == null || _closed) return;
    final resumed = ResumeThread(thread);
    if (resumed.value == 0xffffffff) {
      throw ProcessException('', const [], 'Unable to resume protected action', resumed.error.toInt());
    }
    _closeThread();
  }

  void _closeThread() {
    final thread = _thread;
    if (thread == null) return;
    _closeHandle(thread);
    _thread = null;
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => !_closed && TerminateProcess(_handle, 1).value;
}

int _waitForExit(int address) {
  final handle = HANDLE(Pointer.fromAddress(address));
  final waited = WaitForSingleObject(handle, INFINITE);
  if (waited.value != WAIT_OBJECT_0) throw const ProcessException('', [], 'Unable to wait for process exit');
  return using((arena) {
    final code = arena<Uint32>();
    final result = GetExitCodeProcess(handle, code);
    if (!result.value) throw ProcessException('', const [], 'Unable to read exit code', result.error.toInt());
    return code.value;
  });
}

final class _ClosedInput implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      if (bytes.isNotEmpty) throw StateError('Silent process does not accept stdin injection.');
    }
  }

  @override
  Future<void> close() async {}
}

void _closeHandle(HANDLE handle) {
  final closed = CloseHandle(handle);
  if (!closed.value) throw ProcessException('', const [], 'Unable to close native handle', closed.error.toInt());
}

void _closeDevice(HANDLE handle, ({HANDLE process, HANDLE thread})? launched) {
  try {
    _closeHandle(handle);
  } on ProcessException {
    if (launched != null) {
      TerminateProcess(launched.process, 1);
      CloseHandle(launched.thread);
      CloseHandle(launched.process);
    }
    rethrow;
  }
}

// Match Process.start quoting, including unquoted trailing backslashes passed to cmd.exe.
String _commandLine(String executable, List<String> arguments) => [
  if (executable.contains(' ') && !executable.contains('"')) '"$executable"' else executable,
  for (final argument in arguments)
    if (argument.isEmpty || argument.contains(' ') || argument.contains('\t') || argument.contains('"'))
      WindowsCommandLineQuoter.quoteArgument(argument)
    else
      argument,
].join(' ');

({HANDLE read, HANDLE write}) _createPipe(Pointer<SECURITY_ATTRIBUTES> security, Arena arena) {
  final read = arena<Pointer>();
  final write = arena<Pointer>();
  final result = CreatePipe(read, write, security, 0);
  if (!result.value) throw ProcessException('', const [], 'Unable to create output pipe', result.error.toInt());
  return (read: HANDLE(read.value), write: HANDLE(write.value));
}

Stream<List<int>> _output(int address, int maxBytes) {
  if (address == 0) return const Stream.empty();
  final pending = Isolate.run(() => _drainOutput(address, maxBytes));
  unawaited(pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  return Stream.fromFuture(pending);
}

Uint8List _drainOutput(int address, int maxBytes) {
  final handle = HANDLE(Pointer.fromAddress(address));
  try {
    return using((arena) {
      const chunkSize = 65536;
      final buffer = arena<Uint8>(chunkSize);
      final read = arena<Uint32>();
      final retained = BytesBuilder(copy: false);
      while (true) {
        final result = ReadFile(handle, buffer, chunkSize, read, null);
        if (!result.value) {
          if (result.error == ERROR_BROKEN_PIPE) break;
          throw ProcessException('', const [], 'Unable to drain action output', result.error.toInt());
        }
        if (read.value == 0) break;
        // One extra byte tells the consumer that capture was truncated.
        final remaining = maxBytes + 1 - retained.length;
        if (remaining > 0) {
          retained.add(Uint8List.fromList(buffer.asTypedList(read.value < remaining ? read.value : remaining)));
        }
      }
      return retained.takeBytes();
    });
  } finally {
    _closeHandle(handle);
  }
}
