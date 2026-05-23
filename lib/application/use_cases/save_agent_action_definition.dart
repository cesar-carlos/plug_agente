import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_remote_approval_reconciler.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentActionDefinition {
  SaveAgentActionDefinition(
    this._repository,
    this._validateDefinition,
    this._snapshotter,
    this._featureFlags, {
    AgentActionSecretReferenceFingerprinter? secretReferenceFingerprinter,
  }) : _secretReferenceFingerprinter = secretReferenceFingerprinter;

  final IAgentActionRepository _repository;
  final ValidateAgentActionDefinition _validateDefinition;
  final AgentActionDefinitionSnapshotter _snapshotter;
  final FeatureFlags _featureFlags;
  final AgentActionSecretReferenceFingerprinter? _secretReferenceFingerprinter;
  late final AgentActionRemoteApprovalReconciler _remoteApprovalReconciler = AgentActionRemoteApprovalReconciler(
    _snapshotter,
    secretFingerprinter: _secretReferenceFingerprinter,
  );

  Future<Result<AgentActionDefinition>> call(
    AgentActionDefinition definition,
  ) async {
    final normalizationResult = await _validateDefinition.normalizeForSave(
      definition,
    );
    if (normalizationResult.isError()) {
      return Failure(normalizationResult.exceptionOrNull()!);
    }

    final normalizedDefinition = normalizationResult.getOrThrow();
    final persistedDefinition = normalizedDefinition.copyWith(
      id: normalizedDefinition.id.trim(),
      name: normalizedDefinition.name.trim(),
    );

    final existingRemote = (await _repository.getDefinition(persistedDefinition.id)).getOrNull()?.policies.remote;
    final reconciledRemote = await _remoteApprovalReconciler.reconcileAsync(
      incoming: persistedDefinition.policies.remote,
      previous: existingRemote,
      definition: persistedDefinition,
    );
    var definitionWithRemote = persistedDefinition.copyWith(
      policies: persistedDefinition.policies.copyWith(remote: reconciledRemote),
    );
    if (definitionWithRemote.policies.remote.allowAdHoc && !_featureFlags.enableRemoteAdHocAgentActions) {
      definitionWithRemote = definitionWithRemote.copyWith(
        policies: definitionWithRemote.policies.copyWith(
          remote: definitionWithRemote.policies.remote.copyWith(allowAdHoc: false),
        ),
      );
    }
    if (definitionWithRemote.policies.elevated.runElevated && !_featureFlags.enableElevatedAgentActions) {
      definitionWithRemote = definitionWithRemote.copyWith(
        policies: definitionWithRemote.policies.copyWith(
          elevated: definitionWithRemote.policies.elevated.copyWith(runElevated: false),
        ),
      );
    }

    if (definitionWithRemote.policies.remote.canRunSavedAction) {
      final triggersResult = await _repository.listTriggers(
        actionId: definitionWithRemote.id,
        types: const {AgentActionTriggerType.appClose},
      );
      if (triggersResult.isError()) {
        return Failure(triggersResult.exceptionOrNull()!);
      }

      if (triggersResult.getOrThrow().isNotEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message:
                'Action cannot be approved for remote execution while an app-close trigger exists for this action.',
            code: AgentActionFailureCode.remoteApprovalAppCloseConflict,
            context: {
              'action_id': definitionWithRemote.id,
              'reason': AgentActionTriggerConstants.remoteApprovalAppCloseConflictReason,
              'user_message':
                  'Remova ou exclua o gatilho de encerramento desta acao antes de aprovar a execucao remota pelo hub.',
            },
          ),
        );
      }
    }

    final pendingSnapshotHash = _snapshotter.snapshotHash(definitionWithRemote);
    if (definitionWithRemote.state == AgentActionState.active) {
      final preflightSnapshotHash = _preflightContentSnapshotHash(persistedDefinition);
      final recordedPreflightHash = definition.lastPreflightSnapshotHash ?? definitionWithRemote.lastPreflightSnapshotHash;
      if (recordedPreflightHash == null || recordedPreflightHash != preflightSnapshotHash) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Action preflight validation is required before activation.',
            code: AgentActionFailureCode.preflightRequiredForActive,
            context: {
              'action_id': definitionWithRemote.id,
              'reason': 'preflight_required_for_active',
              'user_message':
                  'Execute "Testar acao" com sucesso antes de salvar esta acao como ativa.',
            },
          ),
        );
      }
    }

    var definitionWithSnapshot = definitionWithRemote.copyWith(
      definitionSnapshotHash: pendingSnapshotHash,
    );
    if (definitionWithRemote.state != AgentActionState.active) {
      final preflightSnapshotHash = _preflightContentSnapshotHash(persistedDefinition);
      if (definitionWithSnapshot.lastPreflightSnapshotHash != null &&
          definitionWithSnapshot.lastPreflightSnapshotHash != preflightSnapshotHash) {
        definitionWithSnapshot = definitionWithSnapshot.copyWith(
          lastPreflightSnapshotHash: null,
        );
      }
    }
    return _repository.saveDefinition(definitionWithSnapshot);
  }

  String _preflightContentSnapshotHash(AgentActionDefinition definition) {
    return _snapshotter.snapshotHash(
      definition.copyWith(state: AgentActionState.needsValidation),
    );
  }
}
