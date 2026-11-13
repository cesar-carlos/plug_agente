import 'package:plug_agente/domain/actions/action_io_lifecycle.dart';
import 'package:result_dart/result_dart.dart';

/// Optional local diagnostics port, separate from the remote I/O contract.
abstract interface class IActionIoLifecycleJournal {
  Future<Result<Unit>> recordMilestone(String executionId, ActionIoMilestone milestone, {int? pid});
  Future<Result<Unit>> recordQueueBlockers(String executionId, List<ActionQueueBlocker> blockers);
}
