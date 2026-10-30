import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:result_dart/result_dart.dart';

final class ActionIoHistoryCursor {
  const ActionIoHistoryCursor(this.createdAt, this.executionId);
  final DateTime createdAt;
  final String executionId;
}

/// Local operator metadata access. Never expose this unscoped port through RPC.
abstract interface class IActionIoLocalHistory {
  static const maxPageSize = 1000;

  Future<Result<List<ActionIoExecutionSnapshot>>> listExecutionSnapshots({
    required int limit,
    ActionIoHistoryCursor? after,
    String? actionId,
    String? idempotencyKey,
    DateTime? requestedAfter,
  });
}
