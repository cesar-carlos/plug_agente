import 'package:plug_agente/domain/actions/action_definition.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_execution.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionPreflight {
  const AgentActionPreflight({
    required this.actionType,
    required this.canRun,
    this.safeMessage,
    this.redactedDiagnostics = const {},
  });

  final AgentActionType actionType;
  final bool canRun;
  final String? safeMessage;
  final Map<String, Object?> redactedDiagnostics;
}

class AgentActionPreparedExecution {
  const AgentActionPreparedExecution({
    required this.actionType,
    required this.redactedCommandPreview,
    this.workingDirectory,
    this.contextHash,
    this.redactedDiagnostics = const {},
  });

  final AgentActionType actionType;
  final String redactedCommandPreview;
  final String? workingDirectory;
  final String? contextHash;
  final Map<String, Object?> redactedDiagnostics;
}

abstract class AgentActionAdapter {
  AgentActionType get type;

  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  );

  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(definition);
  }

  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  });
}
