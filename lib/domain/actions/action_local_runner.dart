import 'package:plug_agente/core/constants/agent_action_resolution_constants.dart';
import 'package:plug_agente/domain/actions/action_definition.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_execution.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_process_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class AgentActionLocalRunner {
  AgentActionType get type;

  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  });

  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  });
}

class AgentActionLocalRunnerRegistry {
  AgentActionLocalRunnerRegistry(Iterable<AgentActionLocalRunner> runners) : _runnersByType = _buildRegistry(runners);

  final Map<AgentActionType, AgentActionLocalRunner> _runnersByType;

  List<AgentActionType> get supportedTypes => List<AgentActionType>.unmodifiable(_runnersByType.keys);

  Result<AgentActionLocalRunner> resolve(AgentActionType type) {
    final runner = _runnersByType[type];
    if (runner == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action type "${type.name}" has no local runner registered.',
          context: {
            'action_type': type.name,
            'reason': AgentActionResolutionConstants.unsupportedLocalActionRunnerReason,
            'user_message': 'Tipo de acao sem executor local registrado: ${type.name}.',
          },
        ),
      );
    }

    return Success(runner);
  }

  static Map<AgentActionType, AgentActionLocalRunner> _buildRegistry(
    Iterable<AgentActionLocalRunner> runners,
  ) {
    final byType = <AgentActionType, AgentActionLocalRunner>{};
    for (final runner in runners) {
      final existing = byType[runner.type];
      if (existing != null) {
        throw StateError(
          'Duplicate local action runner for "${runner.type.name}": '
          '${existing.runtimeType} and ${runner.runtimeType}.',
        );
      }
      byType[runner.type] = runner;
    }

    return Map<AgentActionType, AgentActionLocalRunner>.unmodifiable(byType);
  }
}
