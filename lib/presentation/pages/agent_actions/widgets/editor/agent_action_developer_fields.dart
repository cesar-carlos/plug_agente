import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

/// Flow handlers for [AgentActionDeveloperFields]. Grouped to keep the widget's
/// constructor cohesive; the editor retains the connection-loading orchestration.
class AgentActionDeveloperFieldsCallbacks {
  const AgentActionDeveloperFieldsCallbacks({
    required this.onBinaryPathChanged,
    required this.onPickExecutorPath,
    required this.onPickProjectPath,
    required this.onApplyDefaultExecutorPath,
    required this.onReloadConnections,
    required this.onConfigPathChanged,
    required this.onPickConfigPath,
    required this.onApplyDefaultConfigBinPath,
    required this.onApplyDefaultConfigRootPath,
    required this.onConnectionSearchChanged,
    required this.onConnectionSelected,
    required this.onSubmitted,
  });

  final ValueChanged<String> onBinaryPathChanged;
  final VoidCallback onPickExecutorPath;
  final VoidCallback onPickProjectPath;
  final VoidCallback onApplyDefaultExecutorPath;
  final VoidCallback onReloadConnections;
  final ValueChanged<String> onConfigPathChanged;
  final VoidCallback onPickConfigPath;
  final VoidCallback onApplyDefaultConfigBinPath;
  final VoidCallback onApplyDefaultConfigRootPath;
  final ValueChanged<String> onConnectionSearchChanged;
  final ValueChanged<String?> onConnectionSelected;
  final VoidCallback onSubmitted;
}

/// A selectable Data7 developer connection (id + display label).
typedef AgentActionDeveloperConnectionOption = ({String id, String label});

/// Input fields for a developer (Data7) action draft: executor/project/config
/// paths, connection reload/search/selection, plus contextual hints. The editor
/// owns the controllers and the connection-loading flow ([callbacks]); the
/// computed hint widgets are passed in pre-built.
class AgentActionDeveloperFields extends StatelessWidget {
  const AgentActionDeveloperFields({
    required this.l10n,
    required this.enabled,
    required this.isLoadingConnections,
    required this.usedDefaultConfigPath,
    required this.connectionLookupMessage,
    required this.hasConnections,
    required this.filterHasNoMatches,
    required this.connectionOptions,
    required this.executorPathController,
    required this.projectPathController,
    required this.data7ConfigPathController,
    required this.connectionIdController,
    required this.connectionLabelController,
    required this.connectionSearchController,
    required this.binaryPathHints,
    required this.connectionStatus,
    required this.configPathHints,
    required this.resolvedConfigHints,
    required this.callbacks,
    this.showInlineFeedback = true,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final bool isLoadingConnections;
  final bool usedDefaultConfigPath;
  final String? connectionLookupMessage;
  final bool hasConnections;
  final bool filterHasNoMatches;
  final List<AgentActionDeveloperConnectionOption> connectionOptions;
  final TextEditingController executorPathController;
  final TextEditingController projectPathController;
  final TextEditingController data7ConfigPathController;
  final TextEditingController connectionIdController;
  final TextEditingController connectionLabelController;
  final TextEditingController connectionSearchController;
  final List<Widget> binaryPathHints;
  final List<Widget> connectionStatus;
  final List<Widget> configPathHints;
  final List<Widget> resolvedConfigHints;
  final AgentActionDeveloperFieldsCallbacks callbacks;
  final bool showInlineFeedback;

  @override
  Widget build(BuildContext context) {
    final selectedConnectionId = connectionIdController.text.trim();
    final selectorValue = connectionOptions.any((option) => option.id == selectedConnectionId)
        ? selectedConnectionId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: l10n.agentActionsFormExecutorPath,
                helpTitle: l10n.agentActionsHelpDeveloperTitle,
                helpMessage: l10n.agentActionsHelpDeveloperMessage,
                controller: executorPathController,
                enabled: enabled,
                textInputAction: TextInputAction.next,
                onChanged: callbacks.onBinaryPathChanged,
                suffixIcon: AgentActionEditorPathPickerButton(
                  tooltip: l10n.agentActionsFormBrowseExecutorPath,
                  icon: FluentIcons.open_file,
                  onPressed: enabled ? callbacks.onPickExecutorPath : null,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: l10n.agentActionsFormProjectPath,
                helpTitle: l10n.agentActionsHelpDeveloperTitle,
                helpMessage: l10n.agentActionsHelpDeveloperMessage,
                controller: projectPathController,
                enabled: enabled,
                textInputAction: TextInputAction.next,
                onChanged: callbacks.onBinaryPathChanged,
                suffixIcon: AgentActionEditorPathPickerButton(
                  tooltip: l10n.agentActionsFormBrowseProjectPath,
                  icon: FluentIcons.open_file,
                  onPressed: enabled ? callbacks.onPickProjectPath : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AgentActionEditorDeveloperPathShortcuts(
          primaryLabel: l10n.agentActionsFormUseDefaultExecutorPath,
          onPrimaryPressed: enabled ? callbacks.onApplyDefaultExecutorPath : null,
        ),
        ...binaryPathHints,
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Button(
              onPressed: !enabled || isLoadingConnections ? null : callbacks.onReloadConnections,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoadingConnections)
                    const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    const Icon(FluentIcons.refresh),
                  const SizedBox(width: AppSpacing.xs),
                  Text(l10n.agentActionsFormReloadConnections),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (usedDefaultConfigPath)
              Expanded(
                child: Text(
                  l10n.agentActionsFormDefaultConfigResolved,
                  style: context.bodyMuted,
                ),
              ),
          ],
        ),
        if (showInlineFeedback && connectionLookupMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsValidationTitle),
            content: SelectableText(connectionLookupMessage!),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        ...connectionStatus,
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: l10n.agentActionsFormData7ConfigPath,
                helpTitle: l10n.agentActionsHelpDeveloperTitle,
                helpMessage: l10n.agentActionsHelpDeveloperMessage,
                controller: data7ConfigPathController,
                enabled: enabled,
                textInputAction: TextInputAction.next,
                onChanged: callbacks.onConfigPathChanged,
                suffixIcon: AgentActionEditorPathPickerButton(
                  tooltip: l10n.agentActionsFormBrowseData7ConfigPath,
                  icon: FluentIcons.open_file,
                  onPressed: enabled ? callbacks.onPickConfigPath : null,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: l10n.agentActionsFormConnectionId,
                helpTitle: l10n.agentActionsHelpDeveloperTitle,
                helpMessage: l10n.agentActionsHelpDeveloperMessage,
                controller: connectionIdController,
                enabled: false,
                readOnly: true,
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AgentActionEditorDeveloperPathShortcuts(
          primaryLabel: l10n.agentActionsFormUseDefaultConfigBinPath,
          onPrimaryPressed: enabled ? callbacks.onApplyDefaultConfigBinPath : null,
          secondaryLabel: l10n.agentActionsFormUseDefaultConfigRootPath,
          onSecondaryPressed: enabled ? callbacks.onApplyDefaultConfigRootPath : null,
        ),
        ...configPathHints,
        ...resolvedConfigHints,
        if (hasConnections) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: l10n.agentActionsFormConnectionSearch,
            helpTitle: l10n.agentActionsHelpDeveloperTitle,
            helpMessage: l10n.agentActionsHelpDeveloperMessage,
            controller: connectionSearchController,
            enabled: enabled,
            onChanged: callbacks.onConnectionSearchChanged,
            textInputAction: TextInputAction.search,
          ),
          if (filterHasNoMatches) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.agentActionsFormConnectionFilterEmpty,
              style: context.bodyMuted,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<String>(
          label: l10n.agentActionsFormConnectionSelector,
          helpTitle: l10n.agentActionsHelpDeveloperTitle,
          helpMessage: l10n.agentActionsHelpDeveloperMessage,
          value: selectorValue,
          items: connectionOptions
              .map(
                (AgentActionDeveloperConnectionOption option) => ComboBoxItem<String>(
                  value: option.id,
                  child: Text(option.label),
                ),
              )
              .toList(growable: false),
          onChanged: enabled ? callbacks.onConnectionSelected : null,
          placeholder: Text(l10n.agentActionsFormConnectionSelectorPlaceholder),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormConnectionLabel,
          helpTitle: l10n.agentActionsHelpDeveloperTitle,
          helpMessage: l10n.agentActionsHelpDeveloperMessage,
          controller: connectionLabelController,
          enabled: false,
          readOnly: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => callbacks.onSubmitted(),
        ),
      ],
    );
  }
}
