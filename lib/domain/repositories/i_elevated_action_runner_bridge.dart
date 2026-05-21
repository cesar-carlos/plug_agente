import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Submits an elevated execution request to the Windows helper (execution id only).
abstract interface class IElevatedActionRunnerBridge {
  Future<Result<void>> submitExecution({
    required String executionId,
    required AgentActionDefinition definition,
  });
}
