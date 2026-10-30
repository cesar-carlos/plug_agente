import 'package:plug_agente/application/actions/action_io_stream_export.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:plug_agente/domain/repositories/i_action_io_file_export.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:result_dart/result_dart.dart';

final class ExportActionIoOutput {
  const ExportActionIoOutput(this._output, this._files);

  final IActionIoLocalOutput _output;
  final IActionIoFileExport _files;

  Future<Result<ActionIoExportSummary>> call({
    required String executionId,
    required ActionIoStream stream,
    required String filePath,
    required Future<Result<Unit>> Function() authorize,
  }) => _files.save(
    filePath,
    (write) => ActionIoStreamExport(_output)(
      executionId: executionId,
      stream: stream,
      authorize: authorize,
      write: write,
    ),
    authorize: authorize,
  );
}
