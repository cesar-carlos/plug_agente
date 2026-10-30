import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Checks local approval without the compatibility exemptions of legacy runs.
class ActionIoApprovalGuard {
  const ActionIoApprovalGuard();

  Future<Result<Unit>> validate({
    required AgentActionDefinition definition,
    required AgentActionDefinitionSnapshotter? snapshotter,
    required Future<Map<String, String>> Function()? secretFingerprints,
  }) async {
    final policy = definition.policies.remote;
    if (!definition.canRun ||
        !policy.canRunSavedAction ||
        !policy.allowFaithfulIo ||
        policy.riskFingerprint == null ||
        policy.riskFingerprint!.trim().isEmpty ||
        snapshotter == null ||
        secretFingerprints == null) {
      return _denied();
    }
    try {
      final secrets = await secretFingerprints();
      final fingerprint = snapshotter.riskFingerprint(
        definition,
        secretReferenceFingerprints: secrets.isEmpty ? null : secrets,
      );
      if (fingerprint != policy.riskFingerprint) return _denied();
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Unable to verify local approval for faithful I/O.',
          code: 'ACTION_IO_APPROVAL_UNAVAILABLE',
          cause: error,
        ),
      );
    }
  }

  Result<Unit> _denied() => Failure(
    ActionAuthorizationFailure.withContext(
      message: 'Faithful I/O requires current local approval for this action.',
      code: 'ACTION_IO_NOT_APPROVED',
    ),
  );
}
