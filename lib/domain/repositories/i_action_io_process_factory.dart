import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IActionIoProcessFactory {
  /// Creates a protected suspended process from a locally resolved invocation.
  /// The caller must durably mark starting and reauthorize before this call.
  Future<Result<IActionIoProcess>> start(ActionIoInvocation invocation);
}
