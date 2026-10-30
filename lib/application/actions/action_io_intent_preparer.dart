import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Builds local intents without accepting caller-supplied process definitions.
final class ActionIoIntentPreparer {
  ActionIoIntentPreparer({
    required this.installationId,
    required ActionIoAuthorization authorization,
    required IActionIoSessionLookup sessions,
    required IAgentActionRepository repository,
    required RunAgentActionViaRemoteTrigger triggers,
  }) : _authorization = authorization,
       _sessions = sessions,
       _repository = repository,
       _triggers = triggers;

  final String installationId;
  final ActionIoAuthorization _authorization;
  final IActionIoSessionLookup _sessions;
  final IAgentActionRepository _repository;
  final RunAgentActionViaRemoteTrigger _triggers;

  Future<Result<ActionIoSessionIntent>> prepare({
    required String agentId,
    required String credential,
    required String actionId,
    required String idempotencyKey,
    required bool validateOnly,
    String? triggerId,
  }) async {
    final action = actionId.trim();
    final key = idempotencyKey.trim();
    final selected = triggerId?.trim();
    if (installationId.isEmpty || action.isEmpty || key.isEmpty || selected == '') {
      return Failure(ActionValidationFailure('A saved action and idempotency key are required.'));
    }
    final authority = await _authorization.authorize(
      credential: credential,
      agentId: agentId,
      actionId: action,
      operation: validateOnly ? ActionIoOperation.validateRun : ActionIoOperation.run,
    );
    if (authority.isError()) return Failure(authority.exceptionOrNull()!);
    final client = authority.getOrThrow().clientId;
    final lookup = await _sessions.findExecution(
      installationId: installationId,
      agentId: agentId,
      clientId: client,
      actionId: action,
      idempotencyKey: key,
    );
    if (lookup.isError()) return Failure(lookup.exceptionOrNull()!);
    final original = lookup.getOrThrow().session;
    String resolvedTrigger;
    String definitionHash;
    String? actionType;
    if (original != null) {
      resolvedTrigger = original.triggerId;
      definitionHash = original.definitionHash;
      actionType = original.actionType;
    } else {
      final trigger = await _triggers.resolveEnabledRemoteTriggerId(actionId: action, triggerId: selected);
      if (trigger.isError()) return Failure(trigger.exceptionOrNull()!);
      resolvedTrigger = trigger.getOrThrow();
      final saved = await _repository.getDefinition(action);
      if (saved.isError()) return Failure(saved.exceptionOrNull()!);
      actionType = saved.getOrThrow().type.name;
      definitionHash = const AgentActionDefinitionSnapshotter().snapshotHash(saved.getOrThrow());
    }
    if (resolvedTrigger.isEmpty || definitionHash.isEmpty) {
      return Failure(ActionRuntimeFailure('The original I/O intent snapshot is unavailable.'));
    }
    return Success(
      ActionIoSessionIntent(
        executionId: original?.executionId ?? const Uuid().v4(),
        installationId: installationId,
        agentId: agentId,
        clientId: client,
        actionId: action,
        idempotencyKey: key,
        triggerId: resolvedTrigger,
        definitionHash: definitionHash,
        actionType: actionType,
        fingerprint: sha256.convert(utf8.encode(jsonEncode(['action-io-request-v1', action, selected]))).toString(),
      ),
    );
  }
}
