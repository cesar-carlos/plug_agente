import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_execution_materializer.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_request_protector.dart';
import 'package:result_dart/result_dart.dart';

typedef ElevatedScheduledTaskRunner = Future<ProcessResult> Function(String taskName);

/// Integrates the main app with the Windows elevated helper via request files and schtasks.
class ElevatedActionRunnerBridge implements IElevatedActionRunnerBridge {
  ElevatedActionRunnerBridge({
    required ElevatedActionRequestProtector requestProtector,
    required ElevatedActionExecutionMaterializer materializer,
    ElevatedScheduledTaskRunner? scheduledTaskRunner,
    bool Function()? isWindows,
  }) : _requestProtector = requestProtector,
       _materializer = materializer,
       _scheduledTaskRunner = scheduledTaskRunner ?? _runScheduledTask,
       _isWindows = isWindows ?? (() => Platform.isWindows);

  final ElevatedActionRequestProtector _requestProtector;
  final ElevatedActionExecutionMaterializer _materializer;
  final ElevatedScheduledTaskRunner _scheduledTaskRunner;
  final bool Function() _isWindows;

  @override
  Future<Result<void>> submitExecution({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    if (!_isWindows()) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated agent action runner is only supported on Windows.',
          code: AgentActionFailureCode.elevatedSubmitFailed,
          context: {
            'execution_id': executionId.trim(),
            'phase': AgentActionProcessConstants.elevatedSubmitPhase,
            'reason': AgentActionGateConstants.elevatedSubmitFailedReason,
            'user_message': 'A execucao elevada so esta disponivel no Windows.',
          },
        ),
      );
    }

    final writeResult = await _requestProtector.writeProtectedRequest(executionId: executionId);
    if (writeResult.isError()) {
      return Failure(writeResult.exceptionOrNull()!);
    }
    final protectedRequest = writeResult.getOrThrow();

    final materializeResult = await _materializer.writeMaterializedLaunchPlan(
      protectedRequest: protectedRequest,
      definition: definition,
    );
    if (materializeResult.isError()) {
      return Failure(materializeResult.exceptionOrNull()!);
    }

    try {
      final processResult = await _scheduledTaskRunner(AgentActionElevatedConstants.scheduledTaskName);
      if (processResult.exitCode != 0) {
        // Remove request/materialized artifacts so they don't linger until
        // the periodic purge when schtasks rejects the task immediately.
        _requestProtector.deleteArtifactsForExecution(executionId);
        return Failure(
          ActionRuntimeFailure.withContext(
            message: 'Elevated scheduled task failed to start.',
            code: AgentActionFailureCode.elevatedSubmitFailed,
            context: {
              'execution_id': executionId.trim(),
              'phase': AgentActionProcessConstants.elevatedSubmitPhase,
              'exit_code': processResult.exitCode,
              'reason': AgentActionGateConstants.elevatedSubmitFailedReason,
              'user_message': 'Nao foi possivel acionar o executor elevado. Verifique a tarefa agendada do helper.',
            },
          ),
        );
      }
      return const Success(unit);
    } on Exception catch (error) {
      _requestProtector.deleteArtifactsForExecution(executionId);
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated scheduled task could not be started.',
          code: AgentActionFailureCode.elevatedSubmitFailed,
          cause: error,
          context: {
            'execution_id': executionId.trim(),
            'phase': AgentActionProcessConstants.elevatedSubmitPhase,
            'reason': AgentActionGateConstants.elevatedSubmitFailedReason,
            'user_message': 'Nao foi possivel acionar o executor elevado. Verifique a tarefa agendada do helper.',
          },
        ),
      );
    }
  }

  static Future<ProcessResult> _runScheduledTask(String taskName) {
    return Process.run('schtasks', <String>['/Run', '/TN', taskName]);
  }
}
