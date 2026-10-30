import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';
import 'package:windows_action_runtime/src/windows_bounded_pipe_output.dart';
import 'package:windows_action_runtime/src/windows_pipe_reader.dart';

void main() {
  for (final scenario in [(0, 0), (-1, 0), (0, -2)]) {
    test('worker reports read=${scenario.$1} close=${scenario.$2} without inventing a combined failure', () async {
      final output = WindowsBoundedPipeOutput(
        42,
        nativeApi: _FailingReader(readResult: scenario.$1, closeResult: scenario.$2),
      );
      final received = <int>[];
      Object? failure;
      try {
        await output.stream.forEach(received.addAll);
      } on Object catch (error) {
        failure = error;
      } finally {
        await output.close();
        await output.close();
      }
      expect(received, [0, 255, 26]);
      if (scenario == (0, 0)) {
        expect(failure, isNull);
      } else {
        expect(failure, isNot(isA<WindowsPipeReadCleanupException>()));
        expect(
          failure,
          isA<ProcessException>().having(
            (error) => error.errorCode,
            'original native result',
            scenario.$1 == 0 ? scenario.$2 : scenario.$1,
          ),
        );
      }
    });
  }

  test('worker preserves prefix and both read and cleanup failures across isolate', () async {
    final output = WindowsBoundedPipeOutput(42, nativeApi: _FailingReader());
    final received = <int>[];
    Object? failure;
    try {
      await output.stream.forEach(received.addAll);
    } on Object catch (error) {
      failure = error;
    } finally {
      await output.close();
    }
    expect(received, [0, 255, 26]);
    expect(failure, isA<WindowsPipeReadCleanupException>());
    final combined = failure! as WindowsPipeReadCleanupException;
    expect(combined.cause, isA<ProcessException>().having((e) => e.errorCode, 'read result', -1));
    expect(combined.cleanupFailure, isA<ProcessException>().having((e) => e.errorCode, 'close result', -2));
  });
}

class _FailingReader implements WindowsPipeReadApi {
  _FailingReader({this.readResult = -1, this.closeResult = -2});

  final int readResult;
  final int closeResult;
  int reads = 0;

  @override
  int open(int address, int flags) => 7;

  @override
  int read(int descriptor, Pointer<Uint8> buffer, int capacity) {
    if (reads++ > 0) return readResult;
    buffer.asTypedList(3).setAll(0, [0, 255, 26]);
    return 3;
  }

  @override
  int close(int descriptor) => closeResult;
}
