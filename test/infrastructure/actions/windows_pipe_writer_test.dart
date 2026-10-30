import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_crt_runtime.dart';
import 'package:windows_action_runtime/src/windows_pipe_input_sink.dart';
import 'package:windows_action_runtime/src/windows_pipe_writer.dart';

void main() {
  group('native binary pipe writer', () {
    test('controlled short CRT writes preserve every byte within one block', () {
      using((arena) {
        final pipe = _pipe(arena);
        final api = _ShortCrtWrites();
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address, nativeApi: api);
        final expected = List<int>.generate(1024, (index) => index % 256);
        try {
          final payload = arena<Uint8>(expected.length)..asTypedList(expected.length).setAll(0, expected);
          writer.write(payload, expected.length);
          writer.close();
          expect(api.requests, [1024, 927, 830, 733, 636, 539, 442, 345, 248, 151, 54]);
          expect(api.confirmed, [97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 54]);
          final buffer = arena<Uint8>(expected.length);
          final count = arena<Uint32>();
          expect(ReadFile(pipe.read, buffer, expected.length, count, nullptr).value, isTrue);
          expect(count.value, expected.length);
          expect(buffer.asTypedList(count.value), expected);
          expect(ReadFile(pipe.read, buffer, expected.length, count, nullptr).value, isFalse);
          expect(count.value, 0);
        } finally {
          writer.close();
          expect(CloseHandle(pipe.read).value, isTrue);
        }
      });
    });
    test('close waits for a blocked write before releasing the owned handle', () async {
      const total = 256 * 1024;
      final handles = using((arena) {
        final pipe = _pipe(arena);
        return (read: pipe.read.address, write: pipe.write.address);
      });
      final sink = WindowsPipeInputSink(handles.write);
      final writing = sink.addStream(Stream.value(List<int>.filled(total, 65)));
      var closed = false;
      final closing = sink.close().then((_) => closed = true);
      try {
        // No reader drains the bounded native pipe yet.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(closed, isFalse);
        using((arena) {
          expect(
            GetHandleInformation(HANDLE(Pointer.fromAddress(handles.write)), arena<Uint32>()).value,
            isTrue,
          );
        });
      } finally {
        final received = Isolate.run(() => _readExact(handles.read, total));
        await Future.wait([writing, closing, received]);
        expect(await received, total);
      }
      expect(closed, isTrue);
      using((arena) {
        expect(
          GetHandleInformation(HANDLE(Pointer.fromAddress(handles.write)), arena<Uint32>()).value,
          isFalse,
        );
      });
      await sink.close();
    });

    test('nonblocking native zero progress is reported as failure without confirming bytes', () {
      using((arena) {
        final pipe = _pipe(arena);
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address);
        try {
          final mode = arena<Uint32>()..value = PIPE_NOWAIT;
          expect(SetNamedPipeHandleState(pipe.write, mode, nullptr, nullptr).value, isTrue);
          const length = 65536;
          final payload = arena<Uint8>(length)..asTypedList(length).fillRange(0, length, 65);
          expect(
            () => writer.write(payload, length),
            throwsA(isA<WindowsPipeWriteException>().having((error) => error.confirmedBytes, 'confirmed bytes', 0)),
          );
          writer.close();
          final buffer = arena<Uint8>(length);
          final count = arena<Uint32>();
          expect(ReadFile(pipe.read, buffer, length, count, nullptr).value, isFalse);
          expect(count.value, 0);
        } finally {
          writer.close();
          expect(CloseHandle(pipe.read).value, isTrue);
        }
      });
    });
    test('worker preserves the first block when the native reader closes during the next block', () async {
      const blockBytes = 65536;
      final handles = using((arena) {
        final pipe = _pipe(arena);
        return (read: pipe.read.address, write: pipe.write.address);
      });
      final received = Isolate.run(() => _readExact(handles.read, blockBytes));
      final sink = WindowsPipeInputSink(handles.write);
      final failure = isA<WindowsPipeWriteException>().having(
        (error) => error.confirmedBytes,
        'confirmed first block',
        blockBytes,
      );
      try {
        await expectLater(sink.addStream(Stream.value(List<int>.filled(blockBytes * 2, 65))), throwsA(failure));
        expect(await received, blockBytes);
      } finally {
        await expectLater(sink.close(), throwsA(failure));
      }
    });

    test('preserves CRLF, CTRL-Z, NUL and non-ASCII bytes', () {
      using((arena) {
        final pipe = _pipe(arena);
        const expected = [65, 13, 10, 26, 0, 195, 169, 255];
        final payload = arena<Uint8>(expected.length)..asTypedList(expected.length).setAll(0, expected);
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address);
        writer.write(payload, expected.length);
        writer.close();
        final buffer = arena<Uint8>(expected.length);
        final read = arena<Uint32>();
        expect(ReadFile(pipe.read, buffer, expected.length, read, null).value, isTrue);
        expect(read.value, expected.length);
        expect(buffer.asTypedList(expected.length), expected);
        expect(CloseHandle(pipe.read).value, isTrue);
      });
    });

    test('fromDescriptor continues writing on the adopted pipe', () {
      using((arena) {
        final pipe = _pipe(arena);
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address);
        final continued = WindowsPipeWriter.fromDescriptor(writer.descriptor);
        final payload = arena<Uint8>(4)..asTypedList(4).setAll(0, [1, 2, 3, 4]);
        continued.write(payload, 4);
        continued.close();
        final buffer = arena<Uint8>(4);
        final read = arena<Uint32>();
        expect(ReadFile(pipe.read, buffer, 4, read, null).value, isTrue);
        expect(buffer.asTypedList(4), [1, 2, 3, 4]);
        expect(CloseHandle(pipe.read).value, isTrue);
      });
    });

    test('writes every byte when the payload exceeds one pipe buffer', () async {
      const total = 256 * 1024;
      final handles = using((arena) {
        final pipe = _pipe(arena);
        return (read: pipe.read.address, write: pipe.write.address);
      });
      final received = Isolate.run(() => _readExact(handles.read, total));
      final writer = WindowsPipeWriter.takeOwnership(handles.write);
      try {
        using((arena) {
          final payload = arena<Uint8>(total)..asTypedList(total).fillRange(0, total, 65);
          writer.write(payload, total);
        });
      } finally {
        writer.close();
      }
      expect(await received, total);
    });

    test('closed reader is reported instead of a successful write', () {
      using((arena) {
        final pipe = _pipe(arena);
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address);
        expect(CloseHandle(pipe.read).value, isTrue);
        final payload = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 65);
        expect(
          () => writer.write(payload, 8),
          throwsA(isA<WindowsPipeWriteException>().having((error) => error.confirmedBytes, 'confirmed prefix', 0)),
        );
        writer.close();
      });
    });

    test('write errors are surfaced when the handle is not writable', () {
      using((arena) {
        final pipe = _pipe(arena);
        final writer = WindowsPipeWriter.takeOwnership(pipe.read.address);
        try {
          final payload = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 65);
          expect(() => writer.write(payload, 8), throwsA(isA<ProcessException>()));
        } finally {
          writer.close();
          expect(CloseHandle(pipe.write).value, isTrue);
        }
      });
    });

    test('close releases the owned handle once and refuses further writes', () {
      using((arena) {
        final pipe = _pipe(arena);
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address);
        final flags = arena<Uint32>();
        expect(GetHandleInformation(pipe.write, flags).value, isTrue);
        writer.close();
        expect(GetHandleInformation(pipe.write, flags).value, isFalse);
        final replacement = _pipe(arena);
        writer.close();
        expect(GetHandleInformation(replacement.read, flags).value, isTrue);
        expect(GetHandleInformation(replacement.write, flags).value, isTrue);
        expect(() => writer.write(arena<Uint8>(4), 4), throwsStateError);
        expect(CloseHandle(replacement.read).value, isTrue);
        expect(CloseHandle(replacement.write).value, isTrue);
        expect(CloseHandle(pipe.read).value, isTrue);
      });
    });

    test('rejects invalid buffers before invoking CRT parameter validation', () {
      using((arena) {
        final pipe = _pipe(arena);
        final writer = WindowsPipeWriter.takeOwnership(pipe.write.address);
        try {
          writer.write(nullptr, 0);
          expect(() => writer.write(nullptr, 16), throwsArgumentError);
          expect(() => writer.write(arena<Uint8>(16), -1), throwsArgumentError);
          expect(() => writer.write(arena<Uint8>(16), 0x80000000), throwsArgumentError);
        } finally {
          writer.close();
          expect(CloseHandle(pipe.read).value, isTrue);
        }
      });
    });
  }, skip: !Platform.isWindows);
}

/// Forces short returns while every confirmed byte goes through the real CRT.
/// This does not claim that a blocking Windows pipe spontaneously writes short.
class _ShortCrtWrites implements WindowsPipeWriteApi {
  final DynamicLibrary library = loadWindowsCrtRuntime();
  final requests = <int>[];
  final confirmed = <int>[];

  @override
  int open(int address, int flags) =>
      library.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('_open_osfhandle')(address, flags);

  @override
  int write(int descriptor, Pointer<Uint8> buffer, int length) {
    requests.add(length);
    final result =
        library.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Uint32), int Function(int, Pointer<Uint8>, int)>(
          '_write',
        )(
          descriptor,
          buffer,
          length > 97 ? 97 : length,
        );
    confirmed.add(result);
    return result;
  }

  @override
  int close(int descriptor) => library.lookupFunction<Int32 Function(Int32), int Function(int)>('_close')(descriptor);

  @override
  int releaseHandle(int address) => CloseHandle(HANDLE(Pointer.fromAddress(address))).value ? 0 : GetLastError();
}

int _readExact(int address, int total) {
  final handle = HANDLE(Pointer.fromAddress(address));
  var received = 0;
  using((arena) {
    final buffer = arena<Uint8>(4096);
    final read = arena<Uint32>();
    while (received < total) {
      final result = ReadFile(handle, buffer, 4096, read, null);
      if (!result.value || read.value == 0) {
        throw StateError('Fixture reader stopped after $received of $total bytes.');
      }
      received += read.value;
    }
  });
  if (!CloseHandle(handle).value) throw StateError('Cannot close fixture reader.');
  return received;
}

({HANDLE read, HANDLE write}) _pipe(Arena arena) {
  final read = arena<Pointer>();
  final write = arena<Pointer>();
  if (!CreatePipe(read, write, null, 0).value) throw StateError('Cannot create fixture pipe.');
  return (read: HANDLE(read.value), write: HANDLE(write.value));
}
