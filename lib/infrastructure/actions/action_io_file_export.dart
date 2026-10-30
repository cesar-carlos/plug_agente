import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:plug_agente/domain/repositories/i_action_io_file_export.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoFileExport implements IActionIoFileExport {
  const ActionIoFileExport();

  @override
  Future<Result<ActionIoExportSummary>> save(
    String filePath,
    ActionIoExportProducer produce, {
    required Future<Result<Unit>> Function() authorize,
  }) async {
    if (!p.isAbsolute(filePath)) return Failure(_failure('ACTION_IO_EXPORT_PATH_INVALID'));
    Directory? staging;
    RandomAccessFile? handle;
    Result<ActionIoExportSummary>? result;
    ActionFailure? writeFailure;
    var bytesWritten = 0;
    var published = false;
    try {
      final admission = await authorize();
      if (admission.isError()) return Failure(admission.exceptionOrNull()!);
      staging = await Directory(p.dirname(filePath)).createTemp('.action-io-export-');
      final temporary = File(p.join(staging.path, 'output.bin'));
      handle = await temporary.open(mode: FileMode.write);
      result = await produce((bytes) async {
        if (writeFailure != null) return Failure(writeFailure!);
        if (bytes.length > ActionIoLimits.blockBytes || bytesWritten + bytes.length > ActionIoLimits.executionBytes) {
          writeFailure = _failure('ACTION_IO_EXPORT_LIMIT');
          return Failure(writeFailure!);
        }
        try {
          await handle!.writeFrom(bytes);
          bytesWritten += bytes.length;
          return const Success(unit);
        } on Object catch (error) {
          writeFailure = _failure('ACTION_IO_EXPORT_WRITE_FAILED', cause: error);
          return Failure(writeFailure!);
        }
      });
      if (writeFailure != null) result = Failure(writeFailure!);
      if (result.isSuccess()) {
        if (result.getOrThrow().bytes != bytesWritten) {
          result = Failure(_failure('ACTION_IO_EXPORT_COUNT_MISMATCH'));
        } else {
          await handle.flush();
          await handle.close();
          handle = null;
          final publication = await authorize();
          if (publication.isError()) {
            result = Failure(publication.exceptionOrNull()!);
          } else {
            await temporary.rename(filePath);
            published = true;
          }
        }
      }
    } on ActionFailure catch (error) {
      result = Failure(error);
    } on Object catch (error) {
      result = Failure(_failure('ACTION_IO_EXPORT_FAILED', cause: error));
    }
    try {
      await handle?.close();
      if (staging != null) await staging.delete(recursive: true);
    } on Object catch (error) {
      final primary = result.exceptionOrNull();
      result = Failure(
        ActionRuntimeFailure.withContext(
          message: primary is ActionFailure ? primary.message : 'The export temporary files could not be cleaned up.',
          code: primary is ActionFailure ? primary.code : 'ACTION_IO_EXPORT_CLEANUP_FAILED',
          cause: primary ?? error,
          context: {'destination_written': published, 'cleanup_failed': true},
        ),
      );
    }
    return result;
  }

  ActionFailure _failure(String code, {Object? cause}) => ActionRuntimeFailure.withContext(
    message: 'The output file could not be saved. Check the destination and available disk space.',
    code: code,
    cause: cause,
  );
}
