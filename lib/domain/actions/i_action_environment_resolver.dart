import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Builds the child-process environment from action policy and runtime injection rules.
abstract interface class IActionEnvironmentResolver {
  bool resolveIncludeParentEnvironment({
    required AgentActionEnvironmentPolicy policy,
    String? operationalProfile,
  });

  Future<Result<Map<String, String>>> resolveForProcess({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    String phase = 'execution_preflight',
  });
}
