import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:plug_agente/presentation/providers/agent_actions/action_io_output_preview_controller.dart';
import 'package:result_dart/result_dart.dart';

class _Output implements IActionIoLocalOutput {
  final pending = <Completer<Result<ActionIoReadPage>>>[];
  final cursors = <int>[];
  @override
  Future<Result<ActionIoReadPage>> readLocalOutput({
    required String executionId,
    required int afterSequence,
    required int maxBytes,
  }) {
    expect(maxBytes, ActionIoLimits.blockBytes);
    cursors.add(afterSequence);
    final result = Completer<Result<ActionIoReadPage>>();
    pending.add(result);
    return result.future;
  }
}

ActionIoReadPage _page(int sequence, List<int> bytes) => ActionIoReadPage(
  events: [ActionIoOutputEvent(sequence: sequence, stream: ActionIoStream.stdout, offset: 0, bytes: bytes)],
  nextSequence: sequence,
  terminal: false,
  outputComplete: false,
);

void main() {
  test('replaces bounded preview pages and decodes invalid UTF8 only for display', () async {
    final output = _Output();
    final controller = ActionIoOutputPreviewController(output, executionId: 'e');
    addTearDown(controller.dispose);
    final first = controller.loadNext();
    await controller.loadNext();
    expect(output.pending, hasLength(1));
    final page = _page(1, [0, 255, 65]);
    output.pending[0].complete(Success(page));
    await first;
    expect(controller.stdoutText, '\u0000\uFFFDA');
    expect((page.events.single as ActionIoOutputEvent).bytes, [0, 255, 65]);
    final second = controller.loadNext();
    output.pending[1].complete(Success(_page(2, [66])));
    await second;
    expect(controller.stdoutText, 'B');
    expect(output.cursors, [0, 1]);
    expect(controller.outputComplete, isFalse);
  });
  test('rejects oversized preview without advancing and ignores completion after disposal', () async {
    final output = _Output();
    final controller = ActionIoOutputPreviewController(output, executionId: 'e');
    final load = controller.loadNext();
    output.pending.single.complete(Success(_page(1, List.filled(65537, 65))));
    await load;
    expect(controller.errorCode, 'ACTION_IO_PREVIEW_LIMIT');
    expect(controller.nextSequence, 0);
    final late = controller.loadNext();
    controller.dispose();
    output.pending.last.complete(Success(_page(1, [65])));
    await late;
    expect(controller.stdoutText, isEmpty);
  });
}
