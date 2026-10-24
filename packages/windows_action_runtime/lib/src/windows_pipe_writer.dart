import 'dart:ffi';
import 'dart:io';

import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_crt_runtime.dart';

/// Owns a binary CRT descriptor and its native pipe handle until close.
///
/// `_write` returns the number of bytes accepted, which can be shorter than the
/// request. Zero with bytes still pending means the reader closed the pipe.
final class WindowsPipeWriter {
  WindowsPipeWriter._(this._api, this._descriptor);

  factory WindowsPipeWriter.takeOwnership(int address) {
    if (address <= 0) throw ArgumentError.value(address, 'address', 'Expected an owned pipe handle.');
    try {
      final api = _CrtPipeWriteApi.instance;
      final descriptor = api.open(address, windowsCrtBinaryMode | windowsCrtNoInheritMode);
      if (descriptor < 0) throw const ProcessException('', [], 'Unable to adopt action input pipe');
      return WindowsPipeWriter._(api, descriptor);
    } on Object {
      // Ownership transfers only after successful _open_osfhandle. Failure to
      // resolve the system runtime or allocate a descriptor must not leak it.
      if (!CloseHandle(HANDLE(Pointer.fromAddress(address))).value) {
        throw const ProcessException('', [], 'Unable to release unadopted action input pipe');
      }
      rethrow;
    }
  }

  /// Wraps a descriptor already opened by `WindowsPipeWriter.takeOwnership`.
  ///
  /// CRT descriptors are process-wide, so a later isolate can keep writing
  /// without adopting the Windows handle a second time.
  factory WindowsPipeWriter.fromDescriptor(int descriptor) {
    if (descriptor < 0) {
      throw ArgumentError.value(descriptor, 'descriptor', 'Expected an open CRT descriptor.');
    }
    return WindowsPipeWriter._(_CrtPipeWriteApi.instance, descriptor);
  }

  final _CrtPipeWriteApi _api;
  final int _descriptor;
  bool _closed = false;

  int get descriptor => _descriptor;

  void write(Pointer<Uint8> buffer, int length) {
    if (_closed) throw StateError('Pipe writer is closed.');
    if (length == 0) return;
    if (buffer == nullptr || length < 0 || length > 0x7fffffff) {
      throw ArgumentError('Expected a non-null buffer and length between 1 and INT_MAX.');
    }
    var offset = 0;
    while (offset < length) {
      final pending = length - offset;
      final written = _api.write(_descriptor, buffer + offset, pending);
      if (written < 0) {
        throw ProcessException('', const [], 'Unable to write action input (CRT _write failed)', written);
      }
      if (written == 0 || written > pending) {
        throw const ProcessException('', [], 'Action input pipe closed before the payload was written');
      }
      offset += written;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // _close also closes the underlying Windows handle. Never CloseHandle it
    // again: Windows can reuse that value for an unrelated concurrent pipe.
    final result = _api.close(_descriptor);
    if (result != 0) throw ProcessException('', const [], 'Unable to close action input pipe descriptor', result);
  }
}

final class _CrtPipeWriteApi {
  _CrtPipeWriteApi._(DynamicLibrary library)
    : open = library.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('_open_osfhandle'),
      write = library
          .lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), int Function(int, Pointer<Uint8>, int)>(
            '_write',
          ),
      close = library.lookupFunction<Int32 Function(Int32), int Function(int)>('_close');

  static final _CrtPipeWriteApi instance = _CrtPipeWriteApi._(loadWindowsCrtRuntime());
  final int Function(int, int) open;
  final int Function(int, Pointer<Uint8>, int) write;
  final int Function(int) close;
}
