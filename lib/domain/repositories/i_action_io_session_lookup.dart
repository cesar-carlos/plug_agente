import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IActionIoSessionLookup {
  Future<Result<ActionIoExecutionSnapshot>> getExecutionSnapshot(String executionId);

  /// Reads deduplication state without admitting an intent or reserving bytes.
  Future<Result<ActionIoExecutionLookup>> previewClaim(
    ActionIoSessionIntent intent, {
    required ActionIoConfiguration io,
  });

  Future<Result<ActionIoSessionReference>> getSessionReference(String executionId);
  Future<Result<ActionIoExecutionLookup>> findExecution({
    required String installationId,
    required String agentId,
    required String clientId,
    required String actionId,
    required String idempotencyKey,
  });
}
