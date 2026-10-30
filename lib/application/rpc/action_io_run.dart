import 'package:plug_agente/application/actions/action_io_admission.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_intent_preparer.dart';
import 'package:plug_agente/application/actions/action_io_session_launcher.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/application/rpc/action_io_request_parser.dart';
import 'package:plug_agente/application/rpc/action_io_rpc_mapper.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoRun {
  const ActionIoRun({
    required this.preparer,
    required this.admission,
    required this.launcher,
    required this.supervisor,
    required this.sessions,
    required this.authorization,
  });
  final ActionIoIntentPreparer preparer;
  final ActionIoAdmission admission;
  final ActionIoSessionLauncher launcher;
  final ActionIoSessionSupervisor supervisor;
  final IActionIoSessionLookup sessions;
  final ActionIoAuthorization authorization;

  Future<Map<String, dynamic>> call(RpcRequest request, RpcDispatchContext context) async {
    final params = request.params as Map<String, dynamic>;
    final credential = context.clientToken!;
    final io = ActionIoRequestParser.configuration(params['io']).getOrThrow();
    final intent = (await preparer.prepare(
      agentId: context.agentId,
      credential: credential,
      actionId: params['action_id'] as String,
      idempotencyKey: params['idempotency_key'] as String,
      triggerId: params['trigger_id'] as String?,
      validateOnly: false,
    )).getOrThrow();
    final call = context.actionIo!;
    if (call.isCancelled() || !DateTime.now().isBefore(call.deadline)) {
      throw ActionRuntimeFailure.withContext(
        message: 'The admission deadline expired.',
        code: 'ACTION_IO_REQUEST_EXPIRED',
      );
    }
    final claim = (await admission.admit(
      intent: intent,
      io: io,
      credential: credential,
      isRequestActive: () => !call.isCancelled() && DateTime.now().isBefore(call.deadline),
    )).getOrThrow();
    if (claim.created) {
      final owned = supervisor.launch(
        claim.executionId,
        cancelPending: () async {
          (await launcher.output.cancelQueued(claim.executionId, intent.clientId)).getOrThrow();
          return launcher.queue.cancelPending(claim.executionId);
        },
        execute: () async {
          final saved = await launcher.repository.getDefinition(intent.actionId);
          final Result<Unit> outcome;
          if (saved.isError()) {
            outcome = Failure(saved.exceptionOrNull()!);
          } else {
            outcome = await launcher.execute(
              intent,
              claim: claim,
              credential: credential,
              deadline: saved.getOrThrow().policies.timeout.deadlineFrom(DateTime.now()),
            );
          }
          var snapshot = (await sessions.getExecutionSnapshot(claim.executionId)).getOrThrow();
          if (outcome.isError() && snapshot.processState == 'queued') {
            final error = outcome.exceptionOrNull()!;
            (await launcher.output.finish(
              claim.executionId,
              exitCode: null,
              complete: true,
              failureCode: error is ActionFailure ? error.code : 'ACTION_IO_PREPARATION_FAILED',
            )).getOrThrow();
            snapshot = (await sessions.getExecutionSnapshot(claim.executionId)).getOrThrow();
          }
          // Native cleanup is tracked independently by the supervisor. A failed
          // business result is safe only after its durable terminal projection.
          if (snapshot.processState == 'finished') return const Success(unit);
          return outcome.isError()
              ? outcome
              : Failure(
                  ActionRuntimeFailure.withContext(
                    message: 'Execution finalization is unconfirmed.',
                    code: 'ACTION_OUTCOME_UNKNOWN',
                  ),
                );
        },
      );
      if (owned.isError()) {
        (await launcher.output.cancelQueued(claim.executionId, intent.clientId)).getOrThrow();
        owned.getOrThrow();
      }
    }
    final snapshot = (await sessions.getExecutionSnapshot(claim.executionId)).getOrThrow();
    (await authorization.authorize(
      credential: credential,
      agentId: intent.agentId,
      actionId: intent.actionId,
      ownerClientId: intent.clientId,
      operation: ActionIoOperation.run,
    )).getOrThrow();
    return ActionIoRpcMapper.execution(snapshot, claim: claim);
  }
}
