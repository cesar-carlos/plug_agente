import 'dart:async';

import 'package:plug_agente/application/actions/elevated_action_execution_abort_registry.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
import 'package:result_dart/result_dart.dart';

/// Orchestrates elevated runs: submit execution id to helper, then poll status files.
class ElevatedAgentActionExecutionService {
  ElevatedAgentActionExecutionService({
    required IElevatedActionRunnerBridge bridge,
    required ElevatedActionStatusFileSyncer statusFileSyncer,
    required ElevatedActionRunnerReadinessService readiness,
    ElevatedActionExecutionAbortRegistry? abortRegistry,
    DateTime Function()? now,
  }) : _bridge = bridge,
       _statusFileSyncer = statusFileSyncer,
       _readiness = readiness,
       _abortRegistry = abortRegistry ?? ElevatedActionExecutionAbortRegistry(),
       _now = now ?? DateTime.now;

  final IElevatedActionRunnerBridge _bridge;
  final ElevatedActionStatusFileSyncer _statusFileSyncer;
  final ElevatedActionRunnerReadinessService _readiness;
  final ElevatedActionExecutionAbortRegistry _abortRegistry;
  final DateTime Function() _now;

  Result<void> ensureActionTypeSupported(AgentActionDefinition definition) {
    if (AgentActionElevatedConstants.supportedElevatedActionTypeNames.contains(definition.type.name)) {
      return const Success(unit);
    }

    return Failure(
      ActionValidationFailure.withContext(
        message: 'Action type is not supported by the elevated runner.',
        code: AgentActionFailureCode.unsupportedForElevatedRunner,
        context: {
          'action_id': definition.id,
          'action_type': definition.type.name,
          'reason': AgentActionGateConstants.unsupportedForElevatedRunnerReason,
          'supported_types': AgentActionElevatedConstants.supportedElevatedActionTypeNames.toList(growable: false),
          'user_message':
              'Este tipo de acao ainda nao pode executar no runner elevado. Use execucao local padrao ou outro tipo.',
        },
      ),
    );
  }

  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    final typeGate = ensureActionTypeSupported(definition);
    if (typeGate.isError()) {
      return Failure(typeGate.exceptionOrNull()!);
    }

    final submitResult = await _bridge.submitExecution(
      executionId: executionId,
      definition: definition,
    );
    if (submitResult.isError()) {
      final failure = submitResult.exceptionOrNull()!;
      if (failure is ActionFailure) {
        switch (failure.code) {
          case AgentActionFailureCode.elevatedSubmitFailed:
          case AgentActionFailureCode.elevatedRequestProtectionFailed:
            _readiness.markDegraded(reason: failure.code);
          default:
            break;
        }
      }
      return Failure(failure);
    }

    final startedAt = _now();
    final trimmedExecutionId = executionId.trim();
    _abortRegistry.register(trimmedExecutionId);
    try {
      final terminalResult = await _waitForTerminalOrAbort(
        executionId: trimmedExecutionId,
        processStartedAt: startedAt,
        timeout: definition.policies.timeout.maxRuntime,
      );
      if (terminalResult.isSuccess()) {
        final output = terminalResult.getOrThrow();
        final failureCode = output.failureCode?.trim();
        if (failureCode != null &&
            failureCode.isNotEmpty &&
            AgentActionElevatedConstants.helperDegradedFailureCodes.contains(failureCode)) {
          _readiness.markDegraded(reason: failureCode);
        }
      }
      return terminalResult;
    } finally {
      _abortRegistry.unregister(trimmedExecutionId);
    }
  }

  Future<Result<AgentActionProcessResult>> _waitForTerminalOrAbort({
    required String executionId,
    required DateTime processStartedAt,
    required Duration timeout,
  }) async {
    final completer = Completer<Result<AgentActionProcessResult>>();

    unawaited(
      _statusFileSyncer
          .waitForTerminalResult(
            executionId: executionId,
            processStartedAt: processStartedAt,
            timeout: timeout,
          )
          .then((Result<AgentActionProcessResult> result) {
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          }),
    );

    unawaited(
      _abortRegistry.whenAborted(executionId).then((_) {
        if (completer.isCompleted) {
          return;
        }
        completer.complete(
          Failure(
            ActionRuntimeFailure.withContext(
              message: 'Elevated execution was cancelled before completion.',
              code: AgentActionFailureCode.executionCancelled,
              context: {
                'execution_id': executionId,
                'user_message': 'A execucao elevada foi cancelada.',
              },
            ),
          ),
        );
      }),
    );

    return completer.future;
  }
}
