import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:result_dart/result_dart.dart';

/// Copies one stream's original bytes to a sequential sink with backpressure.
/// The caller owns file creation, finalization and cleanup on failure.
final class ActionIoStreamExport {
  const ActionIoStreamExport(this._output);
  final IActionIoLocalOutput _output;

  Future<Result<ActionIoExportSummary>> call({
    required String executionId,
    required ActionIoStream stream,
    required Future<Result<Unit>> Function() authorize,
    required Future<Result<Unit>> Function(List<int> bytes) write,
  }) async {
    var cursor = 0;
    var written = 0;
    for (;;) {
      final allowed = await authorize();
      if (allowed.isError()) return Failure(allowed.exceptionOrNull()!);
      final result = await _output.readLocalOutput(
        executionId: executionId,
        afterSequence: cursor,
        maxBytes: ActionIoLimits.blockBytes,
      );
      if (result.isError()) return Failure(result.exceptionOrNull()!);
      final page = result.getOrThrow();
      var previous = cursor;
      var pageBytes = 0;
      var completed = false;
      for (final event in page.events) {
        if (completed) return _invalid();
        if (event.sequence != previous + 1 || event.sequence > ActionIoLimits.executionEvents) return _invalid();
        previous = event.sequence;
        if (event is ActionIoOutputEvent) {
          pageBytes += event.bytes.length;
          if (pageBytes > ActionIoLimits.blockBytes) return _invalid();
          if (event.stream != stream) continue;
          if (event.offset != written || written + event.bytes.length > ActionIoLimits.executionBytes) {
            return _invalid();
          }
          final currentPermission = await authorize();
          if (currentPermission.isError()) return Failure(currentPermission.exceptionOrNull()!);
          final saved = await write(event.bytes);
          if (saved.isError()) return Failure(saved.exceptionOrNull()!);
          written += event.bytes.length;
        } else if (event is ActionIoCompletedEvent) {
          if (event.outputComplete != page.outputComplete) return _invalid();
          completed = true;
        }
      }
      if (page.nextSequence != previous) return _invalid();
      cursor = page.nextSequence;
      if (completed || page.events.isEmpty) {
        final currentPermission = await authorize();
        if (currentPermission.isError()) return Failure(currentPermission.exceptionOrNull()!);
        return Success(
          ActionIoExportSummary(
            bytes: written,
            outputComplete: page.outputComplete,
            terminal: page.terminal,
          ),
        );
      }
    }
  }

  Result<ActionIoExportSummary> _invalid() => Failure(
    ActionRuntimeFailure.withContext(
      message: 'The stored output is inconsistent. The export could not be completed.',
      code: 'ACTION_IO_EXPORT_INTEGRITY_FAILED',
    ),
  );
}
