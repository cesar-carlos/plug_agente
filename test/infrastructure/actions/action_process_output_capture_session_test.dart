import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';

void main() {
  test('owns captured bytes when a producer reuses a larger backing buffer', () async {
    final stream = StreamController<List<int>>(sync: true);
    final capture = _capture(stream.stream);
    final backing = Uint8List(1024 * 1024)..fillRange(0, 16, 65);
    stream.add(Uint8List.sublistView(backing, 0, 16));
    backing.fillRange(0, 16, 66);
    await stream.close();
    expect((await capture.result).text, 'A' * 16);
  });

  test('drains a large output but retains only the configured prefix', () async {
    var chunksRead = 0;
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < 4096; i++) {
        chunksRead++;
        yield Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 65);
      }
    }

    final capture = _capture(chunks());
    final output = await capture.result;
    expect(chunksRead, 4096);
    expect(output.text, 'A' * 1024);
    expect(output.isTruncated, isTrue);
  });

  test('cancellation preserves redacted partial output and cancels once', () async {
    var cancellations = 0;
    final stream = StreamController<List<int>>(
      sync: true,
      onCancel: () {
        cancellations++;
      },
    );
    final capture = _capture(stream.stream);
    stream.add('password=secret'.codeUnits);
    final output = await capture.cancel();
    expect(output.isTruncated, isTrue);
    expect(output.text, isNot(contains('secret')));
    expect(stream.hasListener, isFalse);
    expect(await capture.cancel(), same(output));
    expect(cancellations, 1);
    await stream.close();
  });

  test('disabled capture cancels the reader without claiming truncation', () async {
    final stream = StreamController<List<int>>();
    final capture = _capture(stream.stream, enabled: false);
    final output = await capture.cancel();
    expect(output.isCaptured, isFalse);
    expect(output.isTruncated, isFalse);
    expect(stream.hasListener, isFalse);
    await stream.close();
  });

  test('cancellation failure is observable instead of successful truncation', () async {
    final stream = StreamController<List<int>>(
      onCancel: () => Future<void>.error(StateError('cancel failed')),
    );
    final capture = _capture(stream.stream);
    await expectLater(capture.cancel(), throwsStateError);
  });
}

ActionProcessOutputCaptureSession _capture(Stream<List<int>> stream, {int maxBytes = 1024, bool enabled = true}) =>
    ActionProcessOutputCaptureSession(
      stream,
      isEnabled: enabled,
      maxBytes: maxBytes,
      encoding: AgentActionOutputEncodingMode.utf8,
      redactor: const AgentActionRedactor(),
      redactBeforePersisting: true,
    );
