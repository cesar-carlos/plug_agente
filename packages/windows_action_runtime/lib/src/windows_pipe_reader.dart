import 'dart:ffi';
import 'dart:io';

import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_crt_runtime.dart';

/// Owns a binary CRT descriptor and its native pipe handle until close.
///
/// `_read` returns a byte count, zero for EOF, and -1 for errors. This avoids
/// relying on thread-local GetLastError after a Dart/native transition.
final class WindowsPipeReader {
  WindowsPipeReader._(this._api, this._descriptor);

  factory WindowsPipeReader.takeOwnership(int address, {WindowsPipeReadApi? nativeApi}) {
    if (address <= 0) throw ArgumentError.value(address, 'address', 'Expected an owned pipe handle.');
    try {
      final api = nativeApi ?? _CrtPipeApi.instance;
      final descriptor = api.open(address, windowsCrtBinaryMode | windowsCrtNoInheritMode);
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

  final WindowsPipeReadApi _api;
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

abstract interface class WindowsPipeReadApi {
  int open(int address, int flags);
  int read(int descriptor, Pointer<Uint8> buffer, int capacity);
  int close(int descriptor);
}

final class _CrtPipeApi implements WindowsPipeReadApi {
  _CrtPipeApi._(DynamicLibrary library)
    : _open = library.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('_open_osfhandle'),
      _read = library
          .lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), int Function(int, Pointer<Uint8>, int)>(
            '_read',
          ),
      _close = library.lookupFunction<Int32 Function(Int32), int Function(int)>('_close');

  static final _CrtPipeApi instance = _CrtPipeApi._(loadWindowsCrtRuntime());
  final int Function(int, int) _open;
  final int Function(int, Pointer<Uint8>, int) _read;
  final int Function(int) _close;

  @override
  int open(int address, int flags) => _open(address, flags);
  @override
  int read(int descriptor, Pointer<Uint8> buffer, int capacity) => _read(descriptor, buffer, capacity);
  @override
  int close(int descriptor) => _close(descriptor);
}

/// Runs [body] and then closes [reader].
///
/// A failure from [WindowsPipeReader.close] must not replace an error already
/// thrown by [body]: the read failure is the actionable cause.
void closePipeReaderAfter(WindowsPipeReader reader, void Function() body) => preserveActionError(body, reader.close);

/// Runs [body] and then [release]. A failure from [release] never replaces an
/// error already thrown by [body].
void preserveActionError(void Function() body, void Function() release) {
  try {
    body();
  } on Object catch (error, stack) {
    try {
      release();
    } on Object catch (cleanupFailure) {
      Error.throwWithStackTrace(WindowsPipeReadCleanupException(error, cleanupFailure), stack);
    }
    rethrow;
  }
  release();
}

/// Preserves both failures while keeping arbitrary native diagnostics out of text.
final class WindowsPipeReadCleanupException extends ProcessException {
  WindowsPipeReadCleanupException(this.cause, this.cleanupFailure)
    : super('', const [], 'Action output read failed; pipe cleanup also failed');

  final Object cause;
  final Object cleanupFailure;
}
