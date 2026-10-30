import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IActionIoJournal {
  Future<Result<ActionIoSessionClaim>> claim(ActionIoSessionIntent intent, {ActionIoConfiguration? io});

  Future<Result<ActionIoMessageReceipt>> inputStatus(String executionId, String clientId, String messageId);
  Future<Result<Unit>> markStarting(String executionId);
  Future<Result<Unit>> markRunning(String executionId);
  Future<Result<ActionIoInputPoll>> beginNextInput(String executionId);
  Future<Result<ActionIoMessageReceipt>> finishInput(
    String executionId,
    String messageId,
    ActionIoDeliveryState state, {
    required int? confirmedBytes,
    String? failureCode,
  });
  Future<Result<int>> reconcileInterrupted();

  Future<Result<ActionIoMessageReceipt>> admitInput({
    required String executionId,
    required String clientId,
    required String messageId,
    required int sequence,
    required List<int> bytes,
    bool close = false,
    bool internalMessage = false,
  });
}
