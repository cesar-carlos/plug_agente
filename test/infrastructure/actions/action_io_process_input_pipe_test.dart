import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:plug_agente/infrastructure/actions/action_io_process_input_pipe.dart';
import 'package:windows_action_runtime/windows_action_runtime.dart';

final class _PartialConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {
      throw const WindowsPipeWriteException(3);
    }
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('preserves the confirmed prefix and never attributes it to a later write', () async {
    final pipe = ActionIoProcessInputPipe(IOSink(_PartialConsumer()));
    final first = await pipe.write(Uint8List.fromList([0, 255, 13, 10, 26]));
    expect(first.exceptionOrNull(), isA<ActionIoPipeFailure>().having((e) => e.confirmedBytes, 'prefix', 3));
    expect((first.exceptionOrNull()! as ActionIoPipeFailure).cause, isA<WindowsPipeWriteException>());
    await Future<void>.delayed(Duration.zero);
    final later = await pipe.write(Uint8List.fromList([1]));
    expect(later.exceptionOrNull(), isA<ActionIoPipeFailure>().having((e) => e.confirmedBytes, 'unknown', isNull));
    await pipe.close();
  });
}
