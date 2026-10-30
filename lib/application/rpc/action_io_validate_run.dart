import 'package:plug_agente/application/actions/action_io_admission.dart';
import 'package:plug_agente/application/actions/action_io_intent_preparer.dart';
import 'package:plug_agente/application/rpc/action_io_request_parser.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

/// Called only after the I/O handler validates capability, identity and schema.
final class ActionIoValidateRun {
  const ActionIoValidateRun(this._preparer, this._admission);
  final ActionIoIntentPreparer _preparer;
  final ActionIoAdmission _admission;

  Future<Map<String, dynamic>> call(RpcRequest request, RpcDispatchContext context) async {
    final params = request.params as Map<String, dynamic>;
    final io = ActionIoRequestParser.configuration(params['io']).getOrThrow();
    final intent = (await _preparer.prepare(
      agentId: context.agentId,
      credential: context.clientToken!,
      actionId: params['action_id'] as String,
      idempotencyKey: params['idempotency_key'] as String,
      triggerId: params['trigger_id'] as String?,
      validateOnly: true,
    )).getOrThrow();
    final actionType = intent.actionType;
    if (actionType == null) {
      throw ActionRuntimeFailure.withContext(
        message: 'The original action type is unavailable for this execution.',
        code: 'ACTION_IO_SNAPSHOT_UNAVAILABLE',
      );
    }
    final lookup = (await _admission.validate(
      intent: intent,
      io: io,
      credential: context.clientToken!,
    )).getOrThrow();
    return {
      'valid': true,
      'action_id': intent.actionId,
      'action_type': actionType,
      'definition_snapshot_hash': intent.definitionHash,
      'would_replay_existing_execution': lookup.session != null,
      if (lookup.session != null) 'existing_execution_id': lookup.session!.executionId,
    };
  }
}
