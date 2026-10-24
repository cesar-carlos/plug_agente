import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Owns a binary CRT descriptor and its native pipe handle until close.
///
/// `_read` returns a byte count, zero for EOF, and -1 for errors. This avoids
/// relying on thread-local GetLastError after a Dart/native transition.
final class WindowsPipeReader {
  WindowsPipeReader._(this._api, this._descriptor);

  factory WindowsPipeReader.takeOwnership(int address) {
    if (address <= 0) throw ArgumentError.value(address, 'address', 'Expected an owned pipe handle.');
    try {
      final api = _CrtPipeApi.instance;
      final descriptor = api.open(address, _CrtPipeApi.binaryMode | _CrtPipeApi.noInheritMode);
      if (descriptor < 0) throw const ProcessException('', [], 'Unable to adopt action output pipe');
      return WindowsPipeReader._(api, descriptor);
    } on Object {
      // Ownership transfers only after successful _open_osfhandle. Failure to
      // resolve the system runtime or allocate a descriptor must not leak it.
      if (!CloseHandle(HANDLE(Pointer.fromAddress(address))).value) {
        throw const ProcessException('', [], 'Unable to release unadopted action output pipe');
      }
      rethrow;
    }
  }

  final _CrtPipeApi _api;
  final int _descriptor;
  bool _closed = false;

  int read(Pointer<Uint8> buffer, int capacity) {
    if (_closed) throw StateError('Pipe reader is closed.');
    if (buffer == nullptr || capacity <= 0 || capacity > 0x7fffffff) {
      throw ArgumentError('Expected a non-null buffer and capacity between 1 and INT_MAX.');
    }
    final bytes = _api.read(_descriptor, buffer, capacity);
    if (bytes < 0) throw ProcessException('', const [], 'Unable to drain action output (CRT _read failed)', bytes);
    return bytes;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // _close also closes the underlying Windows handle. Never CloseHandle it
    // again: Windows can reuse that value for an unrelated concurrent pipe.
    final result = _api.close(_descriptor);
    if (result != 0) throw ProcessException('', const [], 'Unable to close action output pipe descriptor', result);
  }
}

final class _CrtPipeApi {
  _CrtPipeApi._(DynamicLibrary library)
    : open = library.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('_open_osfhandle'),
      read = library
          .lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), int Function(int, Pointer<Uint8>, int)>(
            '_read',
          ),
      close = library.lookupFunction<Int32 Function(Int32), int Function(int)>('_close');

  static final _CrtPipeApi instance = _CrtPipeApi._(_loadSystemRuntime());
  static const int binaryMode = 0x8000;
  static const int noInheritMode = 0x0080;
  final int Function(int, int) open;
  final int Function(int, Pointer<Uint8>, int) read;
  final int Function(int) close;

  static DynamicLibrary _loadSystemRuntime() => using((arena) {
    const capacity = 32768;
    final path = arena<Uint16>(capacity);
    final directory = GetSystemDirectory(PWSTR(path.cast()), capacity);
    if (directory.value == 0 || directory.value >= capacity) {
      throw const ProcessException('', [], 'Unable to locate the Windows system runtime');
    }
    // Use the OS-provided absolute directory; never search CWD, PATH or a
    // user-configured environment variable for this runtime DLL.
    return DynamicLibrary.open('${path.cast<Utf16>().toDartString()}\\ucrtbase.dll');
  });
}
