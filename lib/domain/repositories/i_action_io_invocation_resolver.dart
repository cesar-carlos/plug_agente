import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoInvocation {
  ActionIoInvocation({
    required this.executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required this.includeParentEnvironment,
    this.workingDirectory,
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment);
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final bool includeParentEnvironment;
}

abstract interface class IActionIoInvocationResolver {
  Future<Result<ActionIoInvocation>> resolve(AgentActionDefinition definition, AgentActionExecutionRequest request);
}
