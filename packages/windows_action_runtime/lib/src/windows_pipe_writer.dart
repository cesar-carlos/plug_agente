import 'dart:ffi';
import 'dart:io';

import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_crt_runtime.dart';

/// Confirmed prefix from successful native calls, not program consumption.
final class WindowsPipeWriteException extends ProcessException {
  const WindowsPipeWriteException(this.confirmedBytes, {this.cleanupFailure})
    : super(
        '',
        const [],
        cleanupFailure == null
            ? 'Action input write failed after a confirmed prefix'
            : 'Action input write failed after a confirmed prefix; pipe close also failed',
      );

  final int confirmedBytes;
  final Object? cleanupFailure;
}

/// Keeps cleanup secondary without exposing arbitrary exception text.
final class WindowsPipeCleanupException extends ProcessException {
  WindowsPipeCleanupException(this.cause, this.cleanupFailure)
    : super('', const [], 'Action input failed; pipe cleanup also failed');

  final Object cause;
  final Object cleanupFailure;
}

/// Retains the adoption failure and the secondary native cleanup diagnostic.
final class WindowsPipeOwnershipException extends ProcessException {
  WindowsPipeOwnershipException(this.cause, this.cleanupErrorCode)
    : super(
        '',
        const [],
        cause is ProcessException ? cause.message : 'Unable to adopt action input pipe',
      );

  final Object cause;
  final int cleanupErrorCode;
}

/// Owns a binary CRT descriptor and its native pipe handle until close.
///
/// `_write` returns the number of bytes accepted, which can be shorter than the
/// request. Zero with bytes still pending means the reader closed the pipe.
final class WindowsPipeWriter {
  WindowsPipeWriter._(this._api, this._descriptor);

  factory WindowsPipeWriter.takeOwnership(int address, {WindowsPipeWriteApi? nativeApi}) {
    if (address <= 0) throw ArgumentError.value(address, 'address', 'Expected an owned pipe handle.');
    try {
      final api = nativeApi ?? _CrtPipeWriteApi.instance;
      final descriptor = api.open(address, windowsCrtBinaryMode | windowsCrtNoInheritMode);
      if (descriptor < 0) throw const ProcessException('', [], 'Unable to adopt action input pipe');
      return WindowsPipeWriter._(api, descriptor);
    } on Object catch (error, stack) {
      // Ownership transfers only after successful _open_osfhandle. Failure to
      // resolve the system runtime or allocate a descriptor must not leak it.
      final cleanupError = nativeApi?.releaseHandle(address) ?? _releaseHandle(address);
      if (cleanupError != 0) {
        Error.throwWithStackTrace(WindowsPipeOwnershipException(error, cleanupError), stack);
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

  final WindowsPipeWriteApi _api;
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
        throw WindowsPipeWriteException(offset);
      }
      if (written == 0 || written > pending) {
        throw WindowsPipeWriteException(offset);
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

/// Native operations used while transferring and retaining pipe ownership.
abstract interface class WindowsPipeWriteApi {
  int open(int address, int flags);
  int write(int descriptor, Pointer<Uint8> buffer, int length);
  int close(int descriptor);

  /// Returns zero on success or the native error captured immediately on failure.
  int releaseHandle(int address);
}

int _releaseHandle(int address) {
  if (CloseHandle(HANDLE(Pointer.fromAddress(address))).value) return 0;
  return GetLastError();
}

final class _CrtPipeWriteApi implements WindowsPipeWriteApi {
  _CrtPipeWriteApi._(DynamicLibrary library)
    : _open = library.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('_open_osfhandle'),
      _write = library
          .lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), int Function(int, Pointer<Uint8>, int)>(
            '_write',
          ),
      _close = library.lookupFunction<Int32 Function(Int32), int Function(int)>('_close');

  static final _CrtPipeWriteApi instance = _CrtPipeWriteApi._(loadWindowsCrtRuntime());
  final int Function(int, int) _open;
  final int Function(int, Pointer<Uint8>, int) _write;
  final int Function(int) _close;

  @override
  int open(int address, int flags) => _open(address, flags);

  @override
  int write(int descriptor, Pointer<Uint8> buffer, int length) => _write(descriptor, buffer, length);

  @override
  int close(int descriptor) => _close(descriptor);

  @override
  int releaseHandle(int address) => _releaseHandle(address);
}
