import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:windows_action_runtime/src/windows_pipe_input_sink.dart';
import 'package:windows_action_runtime/src/windows_pipe_writer.dart';

void main() {
  test('launch failure retains its cause and failed handle cleanup without retry', () async {
    final api = _UnsendableApi();
    final sink = WindowsPipeInputSink(42, nativeApi: api);
    final failure = isA<WindowsPipeOwnershipException>()
        .having((error) => error.cause, 'launch failure', isA<ArgumentError>())
        .having((error) => error.cleanupErrorCode, 'secondary cleanup error', 6);
    try {
      await expectLater(sink.addStream(Stream.value([1])), throwsA(failure));
      await expectLater(sink.close(), throwsA(failure));
      await expectLater(sink.close(), throwsA(failure));
      expect(api.releases, 1);
      expect(api.closes, 0);
    } finally {
      api.unsendable.close();
    }
  });
  test('stream failure remains primary when worker close fails later', () async {
    final api = _NativeApi()..closeResult = -1;
    final sink = WindowsPipeInputSink(42, nativeApi: api);
    final primary = StateError('private source diagnostic');
    await expectLater(sink.addStream(Stream<List<int>>.error(primary)), throwsA(same(primary)));
    await expectLater(
      sink.close(),
      throwsA(
        isA<WindowsPipeCleanupException>()
            .having((error) => error.cause, 'original source failure', same(primary))
            .having((error) => error.cleanupFailure, 'cleanup failure', isA<ProcessException>())
            .having((error) => error.message, 'safe message', isNot(contains('private'))),
      ),
    );
  });
  test('worker retains confirmed progress and reports secondary close failure', () async {
    final api = _NativeApi()
      ..results.addAll([65536, 2, -1])
      ..closeResult = -1;
    final sink = WindowsPipeInputSink(42, nativeApi: api);
    final failure = isA<WindowsPipeWriteException>()
        .having((error) => error.confirmedBytes, 'confirmed prefix', 65538)
        .having(
          (error) => error.cleanupFailure,
          'cleanup diagnostic',
          isA<ProcessException>().having((error) => error.errorCode, 'native close result', -1),
        );
    await expectLater(sink.addStream(Stream.value(List<int>.filled(65540, 65))), throwsA(failure));
    await expectLater(sink.close(), throwsA(failure));
  });
  test('adoption failure remains primary when releasing the handle also fails', () {
    final api = _NativeApi()..openResult = -1;
    expect(
      () => WindowsPipeWriter.takeOwnership(42, nativeApi: api),
      throwsA(
        isA<WindowsPipeOwnershipException>()
            .having(
              (error) => error.message,
              'primary diagnostic',
              'Unable to adopt action input pipe',
            )
            .having((error) => error.cleanupErrorCode, 'secondary native error', 6)
            .having((error) => error.cause, 'original failure', isA<ProcessException>()),
      ),
    );
    expect(api.releases, 1);
    expect(api.closes, 0);
  });

  test('short successful writes continue at the first unconfirmed byte', () {
    final api = _NativeApi()..results.addAll([2, 1, 3]);
    final writer = WindowsPipeWriter.takeOwnership(42, nativeApi: api);
    using((arena) {
      final payload = arena<Uint8>(6)..asTypedList(6).setAll(0, [0, 13, 10, 26, 255, 128]);
      writer.write(payload, 6);
    });
    writer.close();
    expect(api.observed, [0, 13, 10, 26, 255, 128]);
    expect(api.requests, [6, 4, 3]);
    expect(api.closes, 1);
    expect(api.releases, 0);
  });

  for (final terminalResult in [-1, 0, 5]) {
    test('invalid write result $terminalResult preserves only the confirmed prefix', () {
      final api = _NativeApi()..results.addAll([2, terminalResult]);
      final writer = WindowsPipeWriter.takeOwnership(42, nativeApi: api);
      using((arena) {
        final payload = arena<Uint8>(6)..asTypedList(6).fillRange(0, 6, 65);
        expect(
          () => writer.write(payload, 6),
          throwsA(isA<WindowsPipeWriteException>().having((error) => error.confirmedBytes, 'confirmed prefix', 2)),
        );
      });
      writer.close();
      expect(api.requests, [6, 4]);
      expect(api.closes, 1);
    });
  }
}

class _NativeApi implements WindowsPipeWriteApi {
  int openResult = 7;
  int closeResult = 0;
  int releases = 0;
  int closes = 0;
  final results = <int>[];
  final observed = <int>[];
  final requests = <int>[];

  @override
  int open(int address, int flags) => openResult;

  @override
  int releaseHandle(int address) {
    releases++;
    return 6;
  }

  @override
  int close(int descriptor) {
    closes++;
    return closeResult;
  }

  @override
  int write(int descriptor, Pointer<Uint8> buffer, int length) {
    requests.add(length);
    final count = results.removeAt(0);
    if (count > 0 && count <= length) observed.addAll(buffer.asTypedList(count));
    return count;
  }
}

class _UnsendableApi extends _NativeApi {
  final ReceivePort unsendable = ReceivePort();
}
