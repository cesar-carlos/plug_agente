import 'dart:io';

import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';

/// Computes contextual hint data for the developer action draft inputs
/// (executor/project/config paths). Extracted from the editor so the
/// path-inspection logic lives in one focused, testable place.
abstract final class AgentActionDeveloperHints {
  AgentActionDeveloperHints._();

  /// Hints for the executor and project path fields.
  static List<AgentActionEditorDeveloperHintData> binaryPathHints({
    required String executorPath,
    required String projectPath,
    required String defaultExecutorPath,
    required AppLocalizations l10n,
  }) {
    final hints = <AgentActionEditorDeveloperHintData>[];

    if (executorPath.isNotEmpty) {
      final normalizedExecutorPath = AgentActionDraftParsers.normalizePathForComparison(executorPath);
      if (!AgentActionDraftParsers.endsWithFileName(normalizedExecutorPath, 'executor.exe')) {
        hints.add(
          AgentActionEditorDeveloperHintData.warning(l10n.agentActionsFormExecutorPathHintExpectedFileName),
        );
      } else if (normalizedExecutorPath == AgentActionDraftParsers.normalizePathForComparison(defaultExecutorPath)) {
        hints.add(
          AgentActionEditorDeveloperHintData.info(l10n.agentActionsFormExecutorPathHintDefault),
        );
      }
      hints.addAll(
        fileInspectionHints(
          path: executorPath,
          missingMessage: l10n.agentActionsFormExecutorPathHintMissing,
          directoryMessage: l10n.agentActionsFormExecutorPathHintDirectory,
          l10n: l10n,
        ),
      );
    }

    if (projectPath.isNotEmpty) {
      if (!AgentActionDraftParsers.normalizePathForComparison(projectPath).endsWith('.7proj')) {
        hints.add(
          AgentActionEditorDeveloperHintData.warning(l10n.agentActionsFormProjectPathHintExpectedExtension),
        );
      }
      hints.addAll(
        fileInspectionHints(
          path: projectPath,
          missingMessage: l10n.agentActionsFormProjectPathHintMissing,
          directoryMessage: l10n.agentActionsFormProjectPathHintDirectory,
          l10n: l10n,
        ),
      );
    }

    return hints;
  }

  /// Hints for the Data7 config path field.
  static List<AgentActionEditorDeveloperHintData> configPathHints({
    required String configPath,
    required String defaultConfigBinPath,
    required String defaultConfigRootPath,
    required AppLocalizations l10n,
  }) {
    if (configPath.isEmpty) {
      return const <AgentActionEditorDeveloperHintData>[];
    }

    final normalizedConfigPath = AgentActionDraftParsers.normalizePathForComparison(configPath);
    final hints = <AgentActionEditorDeveloperHintData>[];
    if (!AgentActionDraftParsers.endsWithFileName(normalizedConfigPath, 'data7.config')) {
      hints.add(
        AgentActionEditorDeveloperHintData.warning(l10n.agentActionsFormData7ConfigPathHintExpectedFileName),
      );
    } else if (normalizedConfigPath == AgentActionDraftParsers.normalizePathForComparison(defaultConfigBinPath)) {
      hints.add(
        AgentActionEditorDeveloperHintData.info(l10n.agentActionsFormData7ConfigPathHintDefaultBin),
      );
    } else if (normalizedConfigPath == AgentActionDraftParsers.normalizePathForComparison(defaultConfigRootPath)) {
      hints.add(
        AgentActionEditorDeveloperHintData.info(l10n.agentActionsFormData7ConfigPathHintDefaultRoot),
      );
    }
    hints.addAll(
      fileInspectionHints(
        path: configPath,
        missingMessage: l10n.agentActionsFormData7ConfigPathHintMissing,
        directoryMessage: l10n.agentActionsFormData7ConfigPathHintDirectory,
        l10n: l10n,
      ),
    );

    return hints;
  }

  /// Hint describing the resolved (vs typed) Data7 config path.
  static List<AgentActionEditorDeveloperHintData> resolvedConfigHints({
    required String? resolvedConfigPath,
    required String typedConfigPath,
    required AppLocalizations l10n,
  }) {
    final resolvedPath = resolvedConfigPath?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return const <AgentActionEditorDeveloperHintData>[];
    }

    final normalizedResolvedPath = AgentActionDraftParsers.normalizePathForComparison(resolvedPath);
    final normalizedTypedPath = AgentActionDraftParsers.normalizePathForComparison(typedConfigPath.trim());
    final message = normalizedTypedPath.isNotEmpty && normalizedResolvedPath != normalizedTypedPath
        ? l10n.agentActionsFormLoadedConfigPath(resolvedPath)
        : l10n.agentActionsFormResolvedConfigPath(resolvedPath);

    return <AgentActionEditorDeveloperHintData>[
      AgentActionEditorDeveloperHintData.info(message),
    ];
  }

  /// Inspects [path] on disk and warns when it is missing or a directory.
  static List<AgentActionEditorDeveloperHintData> fileInspectionHints({
    required String path,
    required String missingMessage,
    required String directoryMessage,
    required AppLocalizations l10n,
  }) {
    try {
      final entityType = FileSystemEntity.typeSync(path);
      return switch (entityType) {
        FileSystemEntityType.notFound => <AgentActionEditorDeveloperHintData>[
          AgentActionEditorDeveloperHintData.warning(missingMessage),
        ],
        FileSystemEntityType.directory => <AgentActionEditorDeveloperHintData>[
          AgentActionEditorDeveloperHintData.warning(directoryMessage),
        ],
        _ => const <AgentActionEditorDeveloperHintData>[],
      };
    } on FileSystemException {
      return <AgentActionEditorDeveloperHintData>[
        AgentActionEditorDeveloperHintData.warning(l10n.agentActionsFormPathHintInspectionFailed),
      ];
    }
  }
}
