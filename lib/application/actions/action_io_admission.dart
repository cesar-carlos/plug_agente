import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:result_dart/result_dart.dart';

/// Admits locally prepared intents; never starts a process or persists credentials.
/// The caller resolves saved actions/triggers and checks negotiated capability.
final class ActionIoAdmission {
  ActionIoAdmission({
    required ActionIoAuthorization authorization,
    required IActionIoJournal journal,
    required IActionIoSessionLookup sessions,
    required bool Function() accepting,
    required Future<Result<Unit>> Function(ActionIoSessionIntent) validateLocalIntent,
  }) : _authorization = authorization,
       _journal = journal,
       _sessions = sessions,
       _accepting = accepting,
       _validateLocalIntent = validateLocalIntent;

  final ActionIoAuthorization _authorization;
  final IActionIoJournal _journal;
  final IActionIoSessionLookup _sessions;
  final bool Function() _accepting;
  final Future<Result<Unit>> Function(ActionIoSessionIntent) _validateLocalIntent;

  Future<Result<ActionIoExecutionLookup>> validate({
    required ActionIoSessionIntent intent,
    required ActionIoConfiguration io,
    required String credential,
  }) async {
    return _check(intent, io, credential, ActionIoOperation.validateRun);
  }

  Future<Result<ActionIoSessionClaim>> admit({
    required ActionIoSessionIntent intent,
    required ActionIoConfiguration io,
    required String credential,
    bool Function()? isRequestActive,
  }) async {
    final allowed = await _check(intent, io, credential, ActionIoOperation.run);
    if (allowed.isError()) return Failure(allowed.exceptionOrNull()!);
    if (isRequestActive != null && !isRequestActive()) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The admission deadline expired.',
          code: 'ACTION_IO_REQUEST_EXPIRED',
        ),
      );
    }
    final existing = allowed.getOrThrow().session;
    if (existing != null) {
      return Success(
        ActionIoSessionClaim(
          executionId: existing.executionId,
          created: false,
          initialMessageId: io.initialInput == null ? null : ActionIoLimits.initialMessageId,
          closeMessageId: io.closeInput ? ActionIoLimits.closeMessageId : null,
        ),
      );
    }
    return _journal.claim(intent, io: io);
  }

  Future<Result<ActionIoExecutionLookup>> _check(
    ActionIoSessionIntent intent,
    ActionIoConfiguration io,
    String credential,
    ActionIoOperation operation,
  ) async {
    if (!_accepting()) return _closed();
    final authorized = await _authorization.authorize(
      credential: credential,
      agentId: intent.agentId,
      actionId: intent.actionId,
      ownerClientId: intent.clientId,
      operation: operation,
    );
    if (authorized.isError()) return Failure(authorized.exceptionOrNull()!);
    final preview = await _sessions.previewClaim(intent, io: io);
    if (preview.isError()) return Failure(preview.exceptionOrNull()!);
    if (preview.getOrThrow().session == null) {
      final local = await _validateLocalIntent(intent);
      if (local.isError()) return Failure(local.exceptionOrNull()!);
    }
    // Local approval/preflight may await storage. Recheck revocation and drain
    // state immediately before handing the intent to the durable boundary.
    final current = await _authorization.authorize(
      credential: credential,
      agentId: intent.agentId,
      actionId: intent.actionId,
      ownerClientId: intent.clientId,
      operation: operation,
    );
    if (current.isError()) return Failure(current.exceptionOrNull()!);
    if (!_accepting()) return _closed();
    return preview;
  }

  Result<ActionIoExecutionLookup> _closed() => Failure(
    ActionRuntimeFailure.withContext(
      message: 'Remote I/O admission is closed.',
      code: 'ACTION_IO_ADMISSION_CLOSED',
    ),
  );
}
