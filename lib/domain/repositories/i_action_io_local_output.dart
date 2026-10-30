import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:result_dart/result_dart.dart';

/// Local operator read access, separate from Client-authorized RPC access.
/// No input admission or process control is exposed by this port.
abstract interface class IActionIoLocalOutput {
  Future<Result<ActionIoReadPage>> readLocalOutput({
    required String executionId,
    required int afterSequence,
    required int maxBytes,
  });
}
