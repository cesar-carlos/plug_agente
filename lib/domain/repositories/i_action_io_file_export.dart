import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:result_dart/result_dart.dart';

typedef ActionIoExportWriter = Future<Result<Unit>> Function(List<int> bytes);
typedef ActionIoExportProducer = Future<Result<ActionIoExportSummary>> Function(ActionIoExportWriter write);

abstract interface class IActionIoFileExport {
  /// The caller must obtain explicit local permission to replace [filePath].
  Future<Result<ActionIoExportSummary>> save(
    String filePath,
    ActionIoExportProducer produce, {
    required Future<Result<Unit>> Function() authorize,
  });
}
