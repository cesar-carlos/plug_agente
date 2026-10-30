import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/use_cases/export_action_io_output.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:plug_agente/infrastructure/actions/action_io_file_export.dart';
import 'package:result_dart/result_dart.dart';

class _Output implements IActionIoLocalOutput {
  int reads = 0;
  @override
  Future<Result<ActionIoReadPage>> readLocalOutput({
    required String executionId,
    required int afterSequence,
    required int maxBytes,
  }) async {
    reads++;
    expect(executionId, 'execution');
    expect(afterSequence, 0);
    expect(maxBytes, ActionIoLimits.blockBytes);
    return Success(
      ActionIoReadPage(
        events: [
          ActionIoOutputEvent(sequence: 1, stream: ActionIoStream.stdout, offset: 0, bytes: [65]),
          ActionIoOutputEvent(sequence: 2, stream: ActionIoStream.stderr, offset: 0, bytes: [0, 255, 13, 10, 26]),
          const ActionIoCompletedEvent(3, outputComplete: false),
        ],
        nextSequence: 3,
        terminal: true,
        outputComplete: false,
      ),
    );
  }
}

void main() {
  test('composes bounded journal reads with binary file publication and live permission', () async {
    final directory = await Directory.systemTemp.createTemp('action-io-use-case-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File(p.join(directory.path, 'stderr.bin'));
    final output = _Output();
    final export = ExportActionIoOutput(output, const ActionIoFileExport());
    final result = await export(
      executionId: 'execution',
      stream: ActionIoStream.stderr,
      filePath: destination.path,
      authorize: () async => const Success(unit),
    );
    expect(result.getOrThrow().bytes, 5);
    expect(result.getOrThrow().outputComplete, isFalse);
    expect(await destination.readAsBytes(), [0, 255, 13, 10, 26]);

    final denied = ActionAuthorizationFailure('Export is unavailable.');
    final rejected = await export(
      executionId: 'execution',
      stream: ActionIoStream.stdout,
      filePath: destination.path,
      authorize: () async => Failure(denied),
    );
    expect(rejected.exceptionOrNull(), same(denied));
    expect(output.reads, 1);
    expect(await destination.readAsBytes(), [0, 255, 13, 10, 26]);
  });
}
