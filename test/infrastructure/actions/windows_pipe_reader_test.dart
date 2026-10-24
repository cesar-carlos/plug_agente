import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_pipe_reader.dart';

void main() {
  group('native binary pipe reader', () {
    test('closed writers remain EOF under concurrent garbage collection pressure', () async {
      final completed = await Future.wait([
        for (var worker = 0; worker < 4; worker++) Isolate.run(_readClosedPipesUnderGc),
      ]);
      expect(completed, [25000, 25000, 25000, 25000]);
    });

    test('preserves CRLF, CTRL-Z, NUL and non-ASCII bytes before EOF', () {
      using((arena) {
        final pipe = _pipe(arena);
        const expected = [65, 13, 10, 26, 0, 195, 169, 255];
        final payload = arena<Uint8>(expected.length)..asTypedList(expected.length).setAll(0, expected);
        final written = arena<Uint32>();
        expect(WriteFile(pipe.write, payload, expected.length, written, null).value, isTrue);
        expect(CloseHandle(pipe.write).value, isTrue);
        final reader = WindowsPipeReader.takeOwnership(pipe.read.address);
        try {
          final buffer = arena<Uint8>(32);
          expect(reader.read(buffer, 32), expected.length);
          expect(buffer.asTypedList(expected.length), expected);
          expect(reader.read(buffer, 32), 0);
        } finally {
          reader.close();
        }
      });
    });

    test('read errors are surfaced instead of being interpreted as EOF', () {
      using((arena) {
        final pipe = _pipe(arena);
        final reader = WindowsPipeReader.takeOwnership(pipe.write.address);
        try {
          expect(() => reader.read(arena<Uint8>(32), 32), throwsA(isA<ProcessException>()));
        } finally {
          reader.close();
          expect(CloseHandle(pipe.read).value, isTrue);
        }
      });
    });

    test('close releases the owned handle once and refuses further reads', () {
      using((arena) {
        final pipe = _pipe(arena);
        final reader = WindowsPipeReader.takeOwnership(pipe.read.address);
        final flags = arena<Uint32>();
        expect(GetHandleInformation(pipe.read, flags).value, isTrue);
        reader.close();
        expect(GetHandleInformation(pipe.read, flags).value, isFalse);
        final replacement = _pipe(arena);
        reader.close();
        expect(GetHandleInformation(replacement.read, flags).value, isTrue);
        expect(GetHandleInformation(replacement.write, flags).value, isTrue);
        expect(() => reader.read(arena<Uint8>(16), 16), throwsStateError);
        expect(CloseHandle(replacement.read).value, isTrue);
        expect(CloseHandle(replacement.write).value, isTrue);
        expect(CloseHandle(pipe.write).value, isTrue);
      });
    });

    test('preserves the read error when closing also fails', () {
      expect(
        () => preserveActionError(
          () => throw const ProcessException('', [], 'Unable to drain action output (CRT _read failed)', -1),
          () => throw const ProcessException('', [], 'Unable to close action output pipe descriptor', -1),
        ),
        throwsA(
          isA<ProcessException>().having((error) => error.message, 'message', contains('CRT _read failed')),
        ),
      );
    });

    test('preserves a native read failure when close succeeds', () {
      using((arena) {
        final pipe = _pipe(arena);
        final reader = WindowsPipeReader.takeOwnership(pipe.write.address);
        expect(
          () => closePipeReaderAfter(reader, () => reader.read(arena<Uint8>(16), 16)),
          throwsA(
            isA<ProcessException>().having((error) => error.message, 'message', contains('CRT _read failed')),
          ),
        );
        expect(CloseHandle(pipe.read).value, isTrue);
      });
    });

    test('rejects invalid buffers before invoking CRT parameter validation', () {
      using((arena) {
        final pipe = _pipe(arena);
        final reader = WindowsPipeReader.takeOwnership(pipe.read.address);
        try {
          expect(() => reader.read(nullptr, 16), throwsArgumentError);
          expect(() => reader.read(arena<Uint8>(16), 0), throwsArgumentError);
          expect(() => reader.read(arena<Uint8>(16), 0x80000000), throwsArgumentError);
        } finally {
          reader.close();
          expect(CloseHandle(pipe.write).value, isTrue);
        }
      });
    });
  }, skip: !Platform.isWindows);
}

int _readClosedPipesUnderGc() {
  final pressure = <List<int>>[];
  for (var iteration = 0; iteration < 25000; iteration++) {
    pressure.add(List<int>.filled(4096, iteration));
    if (pressure.length > 64) pressure.clear();
    using((arena) {
      final pipe = _pipe(arena);
      if (!CloseHandle(pipe.write).value) throw StateError('Cannot close fixture writer.');
      final reader = WindowsPipeReader.takeOwnership(pipe.read.address);
      try {
        SetLastError(ERROR_ACCESS_DENIED);
        if (reader.read(arena<Uint8>(16), 16) != 0) throw StateError('Closed writer was not EOF.');
      } finally {
        reader.close();
      }
    });
  }
  return 25000;
}

({HANDLE read, HANDLE write}) _pipe(Arena arena) {
  final read = arena<Pointer>();
  final write = arena<Pointer>();
  if (!CreatePipe(read, write, null, 0).value) throw StateError('Cannot create fixture pipe.');
  return (read: HANDLE(read.value), write: HANDLE(write.value));
}
