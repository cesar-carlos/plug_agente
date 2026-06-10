import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_helpers.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_types.dart';
import 'package:result_dart/result_dart.dart';

abstract final class AgentActionPathSnapshotValidator {
  static Result<PathSnapshotCheck> ensurePathSnapshotMatchesCurrent({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    String phase = 'execution_preflight',
  }) {
    final savedCanonicalPath = savedReference?.canonicalPath?.trim();
    if (savedCanonicalPath == null || savedCanonicalPath.isEmpty || currentPath == null) {
      return const Success(PathSnapshotCheck.unchanged());
    }

    if (AgentActionPathValidationHelpers.normalizePathForComparison(savedCanonicalPath) ==
        AgentActionPathValidationHelpers.normalizePathForComparison(currentPath.canonicalPath)) {
      return const Success(PathSnapshotCheck.unchanged());
    }

    return _pathDriftResult(
      actionId: actionId,
      field: field,
      phase: phase,
      policy: savedReference!.effectivePathChangePolicy,
      reason: AgentActionPathContextConstants.pathChangedAfterSaveReason,
      userMessage:
          'O caminho salvo para esta acao mudou desde a validacao anterior. Revise a configuracao e salve novamente.',
      diagnostics: {
        'saved_canonical_path': savedCanonicalPath,
        'current_canonical_path': currentPath.canonicalPath,
      },
    );
  }

  static Result<PathSnapshotCheck> ensureValidationHashMatchesCurrent({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    String phase = 'execution_preflight',
  }) {
    final savedHash = savedReference?.validationHash?.trim();
    final currentHash = currentPath?.contentHash?.trim();
    if (savedHash == null ||
        savedHash.isEmpty ||
        currentHash == null ||
        currentHash.isEmpty ||
        savedHash == currentHash) {
      return const Success(PathSnapshotCheck.unchanged());
    }

    return _pathDriftResult(
      actionId: actionId,
      field: field,
      phase: phase,
      policy: savedReference!.effectivePathChangePolicy,
      reason: AgentActionPathContextConstants.pathContentChangedAfterSaveReason,
      userMessage:
          'O conteudo do arquivo mudou desde a validacao anterior. Revise o arquivo ou atualize a definicao da acao.',
      diagnostics: {
        'saved_validation_hash': savedHash,
        'current_content_hash': currentHash,
      },
    );
  }

  static Result<void> guardPathSnapshot({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    Map<String, Object?>? diagnostics,
    String phase = 'execution_preflight',
  }) {
    final canonicalResult = ensurePathSnapshotMatchesCurrent(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      phase: phase,
    );
    if (canonicalResult.isError()) {
      return Failure(canonicalResult.exceptionOrNull()!);
    }
    _appendPathSnapshotWarning(
      diagnostics: diagnostics,
      field: field,
      check: canonicalResult.getOrThrow(),
    );

    final hashResult = ensureValidationHashMatchesCurrent(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      phase: phase,
    );
    if (hashResult.isError()) {
      return Failure(hashResult.exceptionOrNull()!);
    }
    _appendPathSnapshotWarning(
      diagnostics: diagnostics,
      field: field,
      check: hashResult.getOrThrow(),
      kind: 'content_hash',
    );

    return const Success(unit);
  }

  static void appendPathSnapshotWarningsToDiagnostics({
    required Map<String, Object?> diagnostics,
    required List<Map<String, Object?>> warnings,
  }) {
    if (warnings.isEmpty) {
      return;
    }

    final existing = diagnostics['path_snapshot_warnings'];
    if (existing is List) {
      diagnostics['path_snapshot_warnings'] = <Object?>[
        ...existing,
        ...warnings,
      ];
    } else {
      diagnostics['path_snapshot_warnings'] = warnings;
    }
  }

  static Result<PathSnapshotCheck> _pathDriftResult({
    required String actionId,
    required String field,
    required String phase,
    required AgentActionPathChangePolicy policy,
    required String reason,
    required String userMessage,
    required Map<String, Object?> diagnostics,
  }) {
    return switch (policy) {
      AgentActionPathChangePolicy.allowChanged => const Success(PathSnapshotCheck.unchanged()),
      AgentActionPathChangePolicy.warnIfChanged => Success(
        PathSnapshotCheck.warning(userMessage),
      ),
      AgentActionPathChangePolicy.failIfChanged => Failure(
        ActionValidationFailure.withContext(
          message: 'Path validation snapshot does not match the current state.',
          code: AgentActionFailureCode.pathSnapshotMismatch,
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'reason': reason,
            'path_change_policy': policy.name,
            'user_message': userMessage,
            ...diagnostics,
          },
        ),
      ),
    };
  }

  static void _appendPathSnapshotWarning({
    required Map<String, Object?>? diagnostics,
    required String field,
    required PathSnapshotCheck check,
    String kind = 'canonical_path',
  }) {
    if (diagnostics == null || !check.hasWarning) {
      return;
    }

    appendPathSnapshotWarningsToDiagnostics(
      diagnostics: diagnostics,
      warnings: [
        {
          'field': field,
          'kind': kind,
          'message': check.warningMessage,
        },
      ],
    );
  }
}
