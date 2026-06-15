import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Signals cancellation to the Windows elevated helper for a running execution.
abstract interface class IElevatedActionExecutionCanceller {
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
  });

  /// Best-effort cancellation for all pending elevated bridge requests on shutdown.
  Future<void> cancelAllPendingExecutions();
}
