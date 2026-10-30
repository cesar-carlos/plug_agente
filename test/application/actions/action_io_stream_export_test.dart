import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_stream_export.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:result_dart/result_dart.dart';

class _Output implements IActionIoLocalOutput {
  _Output(this.pages);
  final List<ActionIoReadPage> pages;
  int calls = 0;
  @override
  Future<Result<ActionIoReadPage>> readLocalOutput({
    required String executionId,
    required int afterSequence,
    required int maxBytes,
  }) async {
    expect(maxBytes, ActionIoLimits.blockBytes);
    return Success(pages[calls++]);
  }
}

ActionIoReadPage _page(List<ActionIoEvent> events, int cursor, {bool complete = false}) => ActionIoReadPage(
  events: events,
  nextSequence: cursor,
  terminal: complete,
  outputComplete: complete,
);
Future<Result<Unit>> _allowed() async => const Success(unit);

void main() {
  test('rejects output after completion and contradictory completion metadata', () async {
    final invalidPages = [
      _page(
        [
          const ActionIoCompletedEvent(1, outputComplete: true),
          ActionIoOutputEvent(sequence: 2, stream: ActionIoStream.stdout, offset: 0, bytes: [65]),
        ],
        2,
        complete: true,
      ),
      _page([const ActionIoCompletedEvent(1, outputComplete: false)], 1, complete: true),
    ];
    for (final page in invalidPages) {
      var writes = 0;
      final result = await ActionIoStreamExport(_Output([page]))(
        executionId: 'e',
        stream: ActionIoStream.stdout,
        authorize: _allowed,
        write: (_) async {
          writes++;
          return const Success(unit);
        },
      );
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect((result.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_EXPORT_INTEGRITY_FAILED');
      expect(writes, 0);
    }
  });
  test('exports only the selected original bytes and waits for each write', () async {
    final output = _Output([
      _page([
        ActionIoOutputEvent(sequence: 1, stream: ActionIoStream.stderr, offset: 0, bytes: [99]),
        ActionIoOutputEvent(sequence: 2, stream: ActionIoStream.stdout, offset: 0, bytes: [0, 255, 13, 10]),
      ], 2),
      _page([const ActionIoCompletedEvent(3, outputComplete: true)], 3, complete: true),
    ]);
    final written = <int>[];
    final writing = Completer<Result<Unit>>();
    final started = Completer<void>();
    final export = ActionIoStreamExport(output)(
      executionId: 'e',
      stream: ActionIoStream.stdout,
      authorize: _allowed,
      write: (bytes) {
        written.addAll(bytes);
        started.complete();
        return writing.future;
      },
    );
    await started.future;
    expect(output.calls, 1);
    writing.complete(const Success(unit));
    final summary = (await export).getOrThrow();
    expect(written, [0, 255, 13, 10]);
    expect(summary.bytes, 4);
    expect(summary.outputComplete, isTrue);
  });
  test('revocation after reading prevents delivery to the file', () async {
    final output = _Output([
      _page([
        ActionIoOutputEvent(sequence: 1, stream: ActionIoStream.stdout, offset: 0, bytes: [65]),
      ], 1),
    ]);
    var checks = 0;
    var writes = 0;
    final result = await ActionIoStreamExport(output)(
      executionId: 'e',
      stream: ActionIoStream.stdout,
      authorize: () async =>
          ++checks == 1 ? const Success(unit) : Failure(ActionAuthorizationFailure('Access revoked.')),
      write: (_) async {
        writes++;
        return const Success(unit);
      },
    );
    expect(result.isError(), isTrue);
    expect(writes, 0);
  });
  test('reports an empty pending prefix as incomplete and rejects stream gaps', () async {
    final empty = await ActionIoStreamExport(_Output([_page([], 0)]))(
      executionId: 'e',
      stream: ActionIoStream.stdout,
      authorize: _allowed,
      write: (_) async => const Success(unit),
    );
    expect(empty.getOrThrow().outputComplete, isFalse);
    expect(empty.getOrThrow().terminal, isFalse);
    final bad =
        await ActionIoStreamExport(
          _Output([
            _page([
              ActionIoOutputEvent(sequence: 1, stream: ActionIoStream.stdout, offset: 1, bytes: [65]),
            ], 1),
          ]),
        )(
          executionId: 'e',
          stream: ActionIoStream.stdout,
          authorize: _allowed,
          write: (_) async => fail('Must not write a gap'),
        );
    expect((bad.exceptionOrNull()! as ActionRuntimeFailure).code, 'ACTION_IO_EXPORT_INTEGRITY_FAILED');
  });
}
