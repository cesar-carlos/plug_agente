import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process_factory.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_io_process.dart';
import 'package:result_dart/result_dart.dart';

final class WindowsActionIoProcessFactory implements IActionIoProcessFactory {
  const WindowsActionIoProcessFactory(this._controller);
  final AgentActionProcessTreeController _controller;

  @override
  Future<Result<IActionIoProcess>> start(ActionIoInvocation invocation) async {
    final process = await WindowsActionIoProcess.start(
      executable: invocation.executable,
      arguments: invocation.arguments,
      controller: _controller,
      workingDirectory: invocation.workingDirectory,
      environment: invocation.environment,
      includeParentEnvironment: invocation.includeParentEnvironment,
    );
    if (process.isError()) return Failure(process.exceptionOrNull()!);
    return Success(process.getOrThrow());
  }
}

