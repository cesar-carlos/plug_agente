import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_local_intent_validator.dart';
import 'package:plug_agente/application/actions/action_io_running_session.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_invocation_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process_factory.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Launches only newly claimed durable sessions. Never retries a claim or spawn.
final class ActionIoSessionLauncher {
  const ActionIoSessionLauncher({
    required this.authorization,
    required this.validator,
    required this.repository,
    required this.invocations,
    required this.processes,
    required this.input,
    required this.output,
    required this.queue,
  });
  final ActionIoAuthorization authorization;
  final ActionIoLocalIntentValidator validator;
  final IAgentActionRepository repository;
  final IActionIoInvocationResolver invocations;
  final IActionIoProcessFactory processes;
  final IActionIoJournal input;
  final IActionIoOutputJournal output;
  final ActionIoExecutionQueue queue;

  Future<Result<Unit>> execute(
    ActionIoSessionIntent intent, {
    required ActionIoSessionClaim claim,
    required String credential,
    required DateTime deadline,
  }) async {
    if (!claim.created || claim.executionId != intent.executionId) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Only a newly admitted session may be launched.',
          code: 'ACTION_IO_REPLAY_FORBIDDEN',
        ),
      );
    }
    Future<Result<Unit>> authorize() async {
      final current = await authorization.authorize(
        credential: credential,
        agentId: intent.agentId,
        actionId: intent.actionId,
        ownerClientId: intent.clientId,
        operation: ActionIoOperation.run,
      );
      if (current.isError()) return Failure(current.exceptionOrNull()!);
      return const Success(unit);
    }

    final saved = await repository.getDefinition(intent.actionId);
    if (saved.isError()) return Failure(saved.exceptionOrNull()!);
    ActionIoInvocation? invocation;
    var creationAttempted = false;
    var startingRefused = false;
    final result = await queue.enqueue(
      actionId: intent.actionId,
      executionId: intent.executionId,
      policies: saved.getOrThrow().policies,
      prepare: () async {
        final permitted = await authorize();
        if (permitted.isError()) return permitted;
        final valid = await validator.validate(intent, checkQueue: false);
        if (valid.isError()) return valid;
        if (const AgentActionDefinitionSnapshotter().snapshotHash(saved.getOrThrow()) != intent.definitionHash) {
          return Failure(
            ActionValidationFailure.withContext(
              message: 'The saved action changed before execution.',
              code: 'ACTION_IO_DEFINITION_CHANGED',
            ),
          );
        }
        final resolved = await invocations.resolve(
          saved.getOrThrow(),
          AgentActionExecutionRequest(
            actionId: intent.actionId,
            source: AgentActionRequestSource.remoteHub,
            idempotencyKey: intent.idempotencyKey,
            triggerId: intent.triggerId,
            triggerType: AgentActionTriggerType.remote,
          ),
        );
        if (resolved.isError()) return Failure(resolved.exceptionOrNull()!);
        invocation = resolved.getOrThrow();
        if (!DateTime.now().isBefore(deadline)) {
          return Failure(
            ActionRuntimeFailure.withContext(message: 'The execution deadline has expired.', code: 'ACTION_TIMEOUT'),
          );
        }
        final starting = await input.markStarting(intent.executionId);
        if (starting.isError()) {
          startingRefused = true;
          return starting;
        }
        return authorize();
      },
      create: () async {
        creationAttempted = true;
        final process = await processes.start(invocation!);
        if (process.isError()) return Failure(process.exceptionOrNull()!);
        return Success(
          ActionIoRunningSession(
            executionId: intent.executionId,
            process: process.getOrThrow(),
            inputJournal: input,
            outputJournal: output,
            authorize: authorize,
            deadline: deadline,
            exitCodePolicy: saved.getOrThrow().policies.exitCode,
          ),
        );
      },
    );
    if (result.isError() && !creationAttempted && !startingRefused) {
      final failure = result.exceptionOrNull()!;
      final recorded = await output.finish(
        intent.executionId,
        exitCode: null,
        complete: true,
        failureCode: failure is ActionFailure ? failure.code : 'ACTION_IO_PREPARATION_FAILED',
      );
      if (recorded.isError()) return Failure(recorded.exceptionOrNull()!);
    }
    return result;
  }
}
