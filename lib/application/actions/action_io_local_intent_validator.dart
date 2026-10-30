import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_approval_guard.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Rechecks a newly prepared intent against authoritative saved configuration.
final class ActionIoLocalIntentValidator {
  const ActionIoLocalIntentValidator({
    required IAgentActionRepository repository,
    required AgentActionDefinitionSnapshotter snapshotter,
    required AgentActionSecretReferenceFingerprinter secretFingerprinter,
    required AgentActionExecutionGateChain gates,
    required IActionIoInvocationResolver invocations,
    required ActionExecutionQueue queue,
  }) : _repository = repository,
       _snapshotter = snapshotter,
       _secretFingerprinter = secretFingerprinter,
       _gates = gates,
       _invocations = invocations,
       _queue = queue;

  final IAgentActionRepository _repository;
  final AgentActionDefinitionSnapshotter _snapshotter;
  final AgentActionSecretReferenceFingerprinter _secretFingerprinter;
  final AgentActionExecutionGateChain _gates;
  final IActionIoInvocationResolver _invocations;
  final ActionExecutionQueue _queue;

  Future<Result<Unit>> validate(ActionIoSessionIntent intent, {bool checkQueue = true}) async {
    final saved = await _repository.getDefinition(intent.actionId);
    if (saved.isError()) return Failure(saved.exceptionOrNull()!);
    final definition = saved.getOrThrow();
    if (definition.id != intent.actionId ||
        definition.policies.elevated.runElevated ||
        const {
          AgentActionType.commandLine,
          AgentActionType.email,
          AgentActionType.comObject,
        }.contains(definition.type)) {
      return _refuse('ACTION_IO_EXECUTOR_UNSUPPORTED');
    }
    if (_snapshotter.snapshotHash(definition) != intent.definitionHash) {
      return _refuse('ACTION_IO_DEFINITION_CHANGED');
    }
    final selected = await _repository.getTrigger(intent.triggerId);
    if (selected.isError()) return Failure(selected.exceptionOrNull()!);
    final trigger = selected.getOrThrow();
    if (trigger.id != intent.triggerId ||
        trigger.actionId != definition.id ||
        !trigger.isEnabled ||
        trigger.type != AgentActionTriggerType.remote) {
      return _refuse('ACTION_IO_TRIGGER_UNAVAILABLE');
    }
    final approval = await const ActionIoApprovalGuard().validate(
      definition: definition,
      snapshotter: _snapshotter,
      secretFingerprints: () => _secretFingerprinter.fingerprintsFor(definition),
    );
    if (approval.isError()) return approval;
    final request = AgentActionExecutionRequest(
      actionId: intent.actionId,
      source: AgentActionRequestSource.remoteHub,
      idempotencyKey: intent.idempotencyKey,
      triggerId: intent.triggerId,
      triggerType: AgentActionTriggerType.remote,
    );
    final gated = await _gates.evaluate(faithfulIo: true, request: request);
    if (gated.isError()) return Failure(gated.exceptionOrNull()!);
    if (_snapshotter.snapshotHash(gated.getOrThrow().definition) != intent.definitionHash) {
      return _refuse('ACTION_IO_DEFINITION_CHANGED');
    }
    final invocation = await _invocations.resolve(gated.getOrThrow().definition, request);
    if (invocation.isError()) return Failure(invocation.exceptionOrNull()!);
    if (checkQueue) {
      final queue = _queue.validateRemoteAdmission(actionId: definition.id, policies: definition.policies);
      if (queue.isError()) return Failure(queue.exceptionOrNull()!);
    }
    return const Success(unit);
  }

  Result<Unit> _refuse(String code) => Failure(
    ActionValidationFailure.withContext(
      message: 'The saved action or trigger no longer permits this faithful I/O intent.',
      code: code,
    ),
  );
}
