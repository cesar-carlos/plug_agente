import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_preflight_validity.dart';
import 'package:plug_agente/application/actions/agent_action_remote_approval_reconciler.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_definition_validator.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
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
    AgentActionPreflightSettings? preflightSettings,
    DateTime Function()? now,
  }) : _secretReferenceFingerprinter = secretReferenceFingerprinter,
       _preflightSettings = preflightSettings,
       _now = now ?? DateTime.now;

  final IAgentActionRepository _repository;
  final ValidateAgentActionDefinition _validateDefinition;
  final AgentActionDefinitionSnapshotter _snapshotter;
  final FeatureFlags _featureFlags;
  final AgentActionSecretReferenceFingerprinter? _secretReferenceFingerprinter;
  final AgentActionPreflightSettings? _preflightSettings;
  final DateTime Function() _now;
  late final AgentActionRemoteApprovalReconciler _remoteApprovalReconciler = AgentActionRemoteApprovalReconciler(
    _snapshotter,
    secretFingerprinter: _secretReferenceFingerprinter,
  );

  Future<Result<AgentActionDefinition>> call(
    AgentActionDefinition definition, {
    bool recordPreflight = false,
  }) async {
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

    var policyAdjusted = persistedDefinition;
    if (policyAdjusted.policies.remote.allowAdHoc && !_featureFlags.enableRemoteAdHocAgentActions) {
      policyAdjusted = policyAdjusted.copyWith(
        policies: policyAdjusted.policies.copyWith(
          remote: policyAdjusted.policies.remote.copyWith(allowAdHoc: false),
        ),
      );
    }
    if (policyAdjusted.policies.elevated.runElevated && !_featureFlags.enableElevatedAgentActions) {
      policyAdjusted = policyAdjusted.copyWith(
        policies: policyAdjusted.policies.copyWith(
          elevated: policyAdjusted.policies.elevated.copyWith(runElevated: false),
        ),
      );
    }

    final existingDefinition = (await _repository.getDefinition(policyAdjusted.id)).getOrNull();
    final existingRemote = existingDefinition?.policies.remote;
    final reconciledRemote = await _remoteApprovalReconciler.reconcileAsync(
      incoming: policyAdjusted.policies.remote,
      previous: existingRemote,
      definition: policyAdjusted,
    );
    final definitionWithRemote = policyAdjusted.copyWith(
      policies: policyAdjusted.policies.copyWith(remote: reconciledRemote),
    );

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

    final enabledTriggers = await _repository.listTriggers(actionId: definitionWithRemote.id, isEnabled: true);
    if (enabledTriggers.isError()) return Failure(enabledTriggers.exceptionOrNull()!);
    for (final trigger in enabledTriggers.getOrThrow()) {
      final compatibility = const AgentActionTriggerDefinitionValidator().validate(trigger, definitionWithRemote);
      if (compatibility.isError()) return Failure(compatibility.exceptionOrNull()!);
    }

    final preflightSnapshotHash = _preflightContentSnapshotHash(definitionWithRemote);
    final existingContentHash = existingDefinition == null ? null : _preflightContentSnapshotHash(existingDefinition);
    final storedPreflightAt = existingDefinition?.lastPreflightValidatedAt ?? definition.lastPreflightValidatedAt;
    final canRefreshStoredPreflight =
        !recordPreflight &&
        existingContentHash != null &&
        existingContentHash == preflightSnapshotHash &&
        AgentActionPreflightValidity.isTimestampValid(
          storedPreflightAt,
          now: _now(),
          settings: _preflightSettings,
        );
    final definitionReadyForPreflight = recordPreflight
        ? definitionWithRemote.copyWith(
            lastPreflightSnapshotHash: preflightSnapshotHash,
            lastPreflightValidatedAt: _now().toUtc(),
          )
        : canRefreshStoredPreflight
        ? definitionWithRemote.copyWith(
            lastPreflightSnapshotHash: preflightSnapshotHash,
            lastPreflightValidatedAt: storedPreflightAt,
          )
        : definitionWithRemote;
    final pendingSnapshotHash = _snapshotter.snapshotHash(definitionReadyForPreflight);
    if (definitionReadyForPreflight.state == AgentActionState.active) {
      final usesRefreshedPreflight = recordPreflight || canRefreshStoredPreflight;
      final recordedPreflightHash = usesRefreshedPreflight
          ? definitionReadyForPreflight.lastPreflightSnapshotHash
          : definition.lastPreflightSnapshotHash ?? definitionReadyForPreflight.lastPreflightSnapshotHash;
      final recordedPreflightValidatedAt = usesRefreshedPreflight
          ? definitionReadyForPreflight.lastPreflightValidatedAt
          : definition.lastPreflightValidatedAt ?? definitionReadyForPreflight.lastPreflightValidatedAt;
      if (!AgentActionPreflightValidity.isValid(
        recordedHash: recordedPreflightHash,
        expectedHash: preflightSnapshotHash,
        lastValidatedAt: recordedPreflightValidatedAt,
        now: _now(),
        settings: _preflightSettings,
      )) {
        final isExpired =
            recordedPreflightHash != null &&
            recordedPreflightHash == preflightSnapshotHash &&
            !AgentActionPreflightValidity.isTimestampValid(
              recordedPreflightValidatedAt,
              now: _now(),
              settings: _preflightSettings,
            );
        return Failure(
          ActionValidationFailure.withContext(
            message: isExpired
                ? 'Action preflight validation has expired.'
                : 'Action preflight validation is required before activation.',
            code: isExpired
                ? AgentActionFailureCode.preflightExpiredForActive
                : AgentActionFailureCode.preflightRequiredForActive,
            context: {
              'action_id': definitionWithRemote.id,
              'reason': isExpired ? 'preflight_expired_for_active' : 'preflight_required_for_active',
              if (recordedPreflightValidatedAt != null)
                'last_preflight_validated_at': recordedPreflightValidatedAt.toUtc().toIso8601String(),
              if (AgentActionPreflightValidity.expiresAt(
                    recordedPreflightValidatedAt,
                    settings: _preflightSettings,
                  )
                  case final DateTime expiry)
                'preflight_expires_at': expiry.toIso8601String(),
              'user_message': isExpired
                  ? 'O preflight desta acao expirou. Execute "Testar acao" novamente antes de salvar como Ativa.'
                  : 'Execute "Testar acao" com sucesso antes de salvar esta acao como ativa.',
            },
          ),
        );
      }
    }

    var definitionWithSnapshot = definitionReadyForPreflight.copyWith(
      definitionSnapshotHash: pendingSnapshotHash,
    );
    if (!recordPreflight && definitionReadyForPreflight.state != AgentActionState.active) {
      if (definitionWithSnapshot.lastPreflightSnapshotHash != null &&
          definitionWithSnapshot.lastPreflightSnapshotHash != preflightSnapshotHash) {
        definitionWithSnapshot = definitionWithSnapshot.copyWith(
          lastPreflightSnapshotHash: null,
          lastPreflightValidatedAt: null,
        );
      }
    }
    return _repository.saveDefinition(definitionWithSnapshot);
  }

  String _preflightContentSnapshotHash(AgentActionDefinition definition) {
    return _snapshotter.executionContentHash(definition);
  }
}
