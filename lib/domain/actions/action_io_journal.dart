import 'dart:typed_data';

import 'package:plug_agente/domain/actions/action_io.dart';

final class ActionIoPendingInput {
  ActionIoPendingInput({required this.receipt, required this.close, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final ActionIoMessageReceipt receipt;
  final bool close;
  final Uint8List bytes;
}

final class ActionIoInputPoll {
  const ActionIoInputPoll(this.input);
  final ActionIoPendingInput? input;
}

final class ActionIoSessionIntent {
  const ActionIoSessionIntent({
    required this.executionId,
    required this.installationId,
    required this.agentId,
    required this.clientId,
    required this.actionId,
    required this.idempotencyKey,
    required this.fingerprint,
    required this.triggerId,
    required this.definitionHash,
    this.actionType,
  });
  final String executionId;
  final String installationId;
  final String agentId;
  final String clientId;
  final String actionId;
  final String idempotencyKey;
  final String fingerprint;
  final String triggerId;
  final String definitionHash;
  final String? actionType;
}

final class ActionIoSessionClaim {
  const ActionIoSessionClaim({
    required this.executionId,
    required this.created,
    this.initialMessageId,
    this.closeMessageId,
  });
  final String executionId;
  final bool created;
  final String? initialMessageId;
  final String? closeMessageId;
}

final class ActionIoMessageReceipt {
  const ActionIoMessageReceipt({
    required this.executionId,
    required this.messageId,
    required this.sequence,
    required this.state,
    required this.confirmedBytes,
    required this.nextInputSequence,
    required this.stdinState,
  });
  final String executionId;
  final String messageId;
  final int sequence;
  final ActionIoDeliveryState state;
  final int? confirmedBytes;
  final int nextInputSequence;
  final ActionIoStdinState stdinState;
}
