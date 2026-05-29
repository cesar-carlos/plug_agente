import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

/// Input fields for a command-line action draft.
class AgentActionCommandLineFields extends StatelessWidget {
  const AgentActionCommandLineFields({
    required this.l10n,
    required this.enabled,
    required this.commandController,
    required this.workingDirectoryController,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController commandController;
  final TextEditingController workingDirectoryController;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormCommand,
          helpTitle: l10n.agentActionsHelpCommandTitle,
          helpMessage: l10n.agentActionsHelpCommandMessage,
          controller: commandController,
          enabled: enabled,
          maxLines: 2,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormWorkingDirectory,
          helpTitle: l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: workingDirectoryController,
          enabled: enabled,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

/// Input fields for an executable action draft.
class AgentActionExecutableFields extends StatelessWidget {
  const AgentActionExecutableFields({
    required this.l10n,
    required this.enabled,
    required this.executableTargetPathController,
    required this.argumentsController,
    required this.workingDirectoryController,
    required this.onPickExecutablePath,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController executableTargetPathController;
  final TextEditingController argumentsController;
  final TextEditingController workingDirectoryController;
  final VoidCallback onPickExecutablePath;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormExecutablePath,
          helpTitle: l10n.agentActionsHelpPathTitle,
          helpMessage: l10n.agentActionsHelpPathMessage,
          controller: executableTargetPathController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          suffixIcon: AgentActionEditorPathPickerButton(
            tooltip: l10n.agentActionsFormBrowseExecutablePath,
            icon: FluentIcons.open_file,
            onPressed: enabled ? onPickExecutablePath : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormArguments,
          helpTitle: l10n.agentActionsHelpArgumentsTitle,
          helpMessage: l10n.agentActionsHelpArgumentsMessage,
          controller: argumentsController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormWorkingDirectory,
          helpTitle: l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: workingDirectoryController,
          enabled: enabled,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

/// Input fields for a COM object action draft.
class AgentActionComObjectFields extends StatelessWidget {
  const AgentActionComObjectFields({
    required this.l10n,
    required this.enabled,
    required this.comProgIdController,
    required this.comMemberNameController,
    required this.comArgumentsController,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController comProgIdController;
  final TextEditingController comMemberNameController;
  final TextEditingController comArgumentsController;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormComProgId,
          helpTitle: l10n.agentActionsHelpComTitle,
          helpMessage: l10n.agentActionsHelpComMessage,
          controller: comProgIdController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormComMemberName,
          helpTitle: l10n.agentActionsHelpComTitle,
          helpMessage: l10n.agentActionsHelpComMessage,
          controller: comMemberNameController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormComArguments,
          helpTitle: l10n.agentActionsHelpComTitle,
          helpMessage: l10n.agentActionsHelpComMessage,
          controller: comArgumentsController,
          enabled: enabled,
          maxLines: 8,
          textInputAction: TextInputAction.done,
          hint: l10n.agentActionsFormComArgumentsHint,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

/// Input fields for an email action draft.
class AgentActionEmailFields extends StatelessWidget {
  const AgentActionEmailFields({
    required this.l10n,
    required this.enabled,
    required this.smtpProfileIdController,
    required this.fromController,
    required this.toController,
    required this.ccController,
    required this.bccController,
    required this.subjectController,
    required this.bodyController,
    required this.attachmentsController,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController smtpProfileIdController;
  final TextEditingController fromController;
  final TextEditingController toController;
  final TextEditingController ccController;
  final TextEditingController bccController;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final TextEditingController attachmentsController;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormSmtpProfileId,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: smtpProfileIdController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormSmtpProfileIdHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailFrom,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: fromController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailTo,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: toController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailToHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailCc,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: ccController,
          enabled: enabled,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailCcHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailBcc,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: bccController,
          enabled: enabled,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailBccHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailSubject,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: subjectController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailSubjectHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailBody,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: bodyController,
          enabled: enabled,
          maxLines: 8,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormEmailBodyHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEmailAttachments,
          helpTitle: l10n.agentActionsHelpEmailTitle,
          helpMessage: l10n.agentActionsHelpEmailMessage,
          controller: attachmentsController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          hint: l10n.agentActionsFormEmailAttachmentsHint,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

/// Input fields for a JAR action draft.
class AgentActionJarFields extends StatelessWidget {
  const AgentActionJarFields({
    required this.l10n,
    required this.enabled,
    required this.jarPathController,
    required this.javaExecutablePathController,
    required this.argumentsController,
    required this.workingDirectoryController,
    required this.onPickJarPath,
    required this.onPickJavaExecutablePath,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController jarPathController;
  final TextEditingController javaExecutablePathController;
  final TextEditingController argumentsController;
  final TextEditingController workingDirectoryController;
  final VoidCallback onPickJarPath;
  final VoidCallback onPickJavaExecutablePath;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormJarPath,
          helpTitle: l10n.agentActionsHelpJarTitle,
          helpMessage: l10n.agentActionsHelpJarMessage,
          controller: jarPathController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          suffixIcon: AgentActionEditorPathPickerButton(
            tooltip: l10n.agentActionsFormBrowseJarPath,
            icon: FluentIcons.open_file,
            onPressed: enabled ? onPickJarPath : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormJavaExecutablePath,
          helpTitle: l10n.agentActionsHelpInterpreterTitle,
          helpMessage: l10n.agentActionsHelpInterpreterMessage,
          controller: javaExecutablePathController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormJavaExecutablePathHint,
          suffixIcon: AgentActionEditorPathPickerButton(
            tooltip: l10n.agentActionsFormBrowseJavaExecutablePath,
            icon: FluentIcons.open_file,
            onPressed: enabled ? onPickJavaExecutablePath : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormArguments,
          helpTitle: l10n.agentActionsHelpArgumentsTitle,
          helpMessage: l10n.agentActionsHelpArgumentsMessage,
          controller: argumentsController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormWorkingDirectory,
          helpTitle: l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: workingDirectoryController,
          enabled: enabled,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

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
    required this.onConnectionIdChanged,
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
  final ValueChanged<String> onConnectionIdChanged;
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
        if (connectionLookupMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsValidationTitle),
            content: Text(connectionLookupMessage!),
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
                enabled: enabled,
                textInputAction: TextInputAction.next,
                onChanged: callbacks.onConnectionIdChanged,
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

/// Input fields for a PowerShell action draft (mode + host + command/script).
class AgentActionPowerShellDraftFields extends StatelessWidget {
  const AgentActionPowerShellDraftFields({
    required this.l10n,
    required this.enabled,
    required this.modeDisplayEnabled,
    required this.isEditing,
    required this.mode,
    required this.executable,
    required this.isModeUnavailable,
    required this.modeDisplayController,
    required this.commandController,
    required this.scriptPathController,
    required this.argumentsController,
    required this.workingDirectoryController,
    required this.modeDropdownKey,
    required this.executableDropdownKey,
    required this.onModeChanged,
    required this.onExecutableChanged,
    required this.onPickScriptPath,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final bool modeDisplayEnabled;
  final bool isEditing;
  final PowerShellDraftMode mode;
  final PowerShellExecutable executable;
  final bool Function(PowerShellDraftMode mode) isModeUnavailable;
  final TextEditingController modeDisplayController;
  final TextEditingController commandController;
  final TextEditingController scriptPathController;
  final TextEditingController argumentsController;
  final TextEditingController workingDirectoryController;
  final Key modeDropdownKey;
  final Key executableDropdownKey;
  final ValueChanged<PowerShellDraftMode> onModeChanged;
  final ValueChanged<PowerShellExecutable> onExecutableChanged;
  final VoidCallback onPickScriptPath;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final modeField = isEditing
        ? AppTextField(
            key: modeDropdownKey,
            label: l10n.agentActionsFormPowerShellMode,
            helpTitle: l10n.agentActionsHelpPowerShellModeTitle,
            helpMessage: l10n.agentActionsHelpPowerShellModeMessage,
            controller: modeDisplayController,
            enabled: modeDisplayEnabled,
            readOnly: true,
            textInputAction: TextInputAction.next,
          )
        : AppDropdown<PowerShellDraftMode>(
            key: modeDropdownKey,
            label: l10n.agentActionsFormPowerShellMode,
            helpTitle: l10n.agentActionsHelpPowerShellModeTitle,
            helpMessage: l10n.agentActionsHelpPowerShellModeMessage,
            value: mode,
            items: PowerShellDraftMode.values
                .map(
                  (PowerShellDraftMode item) {
                    final unavailable = isModeUnavailable(item);
                    final label = powerShellDraftModeLabel(item, l10n);
                    return ComboBoxItem<PowerShellDraftMode>(
                      value: item,
                      enabled: !unavailable,
                      child: Text(
                        unavailable ? '$label (${l10n.agentActionsRiskRunnerUnavailable})' : label,
                      ),
                    );
                  },
                )
                .toList(growable: false),
            onChanged: enabled
                ? (PowerShellDraftMode? value) {
                    if (value == null || value == mode || isModeUnavailable(value)) {
                      return;
                    }
                    onModeChanged(value);
                  }
                : null,
          );
    final executableField = AppDropdown<PowerShellExecutable>(
      key: executableDropdownKey,
      label: l10n.agentActionsFormPowerShellExecutable,
      helpTitle: l10n.agentActionsHelpPowerShellExecutableTitle,
      helpMessage: l10n.agentActionsHelpPowerShellExecutableMessage,
      value: executable,
      items: PowerShellExecutable.values
          .map(
            (PowerShellExecutable item) => ComboBoxItem<PowerShellExecutable>(
              value: item,
              child: Text(powerShellExecutableLabel(item, l10n)),
            ),
          )
          .toList(growable: false),
      onChanged: enabled
          ? (PowerShellExecutable? value) {
              if (value == null || value == executable) {
                return;
              }
              onExecutableChanged(value);
            }
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 220, child: modeField),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 240, child: executableField),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (mode == PowerShellDraftMode.inline) ...[
          AppTextField(
            label: l10n.agentActionsFormPowerShellCommand,
            helpTitle: l10n.agentActionsHelpPowerShellCommandTitle,
            helpMessage: l10n.agentActionsHelpPowerShellCommandMessage,
            controller: commandController,
            enabled: enabled,
            maxLines: 4,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else ...[
          AppTextField(
            label: l10n.agentActionsFormPowerShellScriptPath,
            helpTitle: l10n.agentActionsHelpPowerShellScriptTitle,
            helpMessage: l10n.agentActionsHelpPowerShellScriptMessage,
            controller: scriptPathController,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            suffixIcon: AgentActionEditorPathPickerButton(
              tooltip: l10n.agentActionsFormBrowsePowerShellScriptPath,
              icon: FluentIcons.open_file,
              onPressed: enabled ? onPickScriptPath : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: l10n.agentActionsFormArguments,
            helpTitle: l10n.agentActionsHelpArgumentsTitle,
            helpMessage: l10n.agentActionsHelpArgumentsMessage,
            controller: argumentsController,
            enabled: enabled,
            maxLines: 4,
            textInputAction: TextInputAction.next,
            hint: l10n.agentActionsFormArgumentsHint,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppTextField(
          label: l10n.agentActionsFormWorkingDirectory,
          helpTitle: l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: workingDirectoryController,
          enabled: enabled,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

/// Input fields for a script action draft.
class AgentActionScriptFields extends StatelessWidget {
  const AgentActionScriptFields({
    required this.l10n,
    required this.enabled,
    required this.scriptPathController,
    required this.interpreterPathController,
    required this.argumentsController,
    required this.workingDirectoryController,
    required this.onPickScriptPath,
    required this.onPickInterpreterPath,
    required this.onSubmitted,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final TextEditingController scriptPathController;
  final TextEditingController interpreterPathController;
  final TextEditingController argumentsController;
  final TextEditingController workingDirectoryController;
  final VoidCallback onPickScriptPath;
  final VoidCallback onPickInterpreterPath;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: l10n.agentActionsFormScriptPath,
          helpTitle: l10n.agentActionsHelpPathTitle,
          helpMessage: l10n.agentActionsHelpPathMessage,
          controller: scriptPathController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          suffixIcon: AgentActionEditorPathPickerButton(
            tooltip: l10n.agentActionsFormBrowseScriptPath,
            icon: FluentIcons.open_file,
            onPressed: enabled ? onPickScriptPath : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormInterpreterPath,
          helpTitle: l10n.agentActionsHelpInterpreterTitle,
          helpMessage: l10n.agentActionsHelpInterpreterMessage,
          controller: interpreterPathController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormInterpreterPathHint,
          suffixIcon: AgentActionEditorPathPickerButton(
            tooltip: l10n.agentActionsFormBrowseInterpreterPath,
            icon: FluentIcons.open_file,
            onPressed: enabled ? onPickInterpreterPath : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormArguments,
          helpTitle: l10n.agentActionsHelpArgumentsTitle,
          helpMessage: l10n.agentActionsHelpArgumentsMessage,
          controller: argumentsController,
          enabled: enabled,
          maxLines: 4,
          textInputAction: TextInputAction.next,
          hint: l10n.agentActionsFormArgumentsHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormWorkingDirectory,
          helpTitle: l10n.agentActionsHelpWorkingDirectoryTitle,
          helpMessage: l10n.agentActionsHelpWorkingDirectoryMessage,
          controller: workingDirectoryController,
          enabled: enabled,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}
