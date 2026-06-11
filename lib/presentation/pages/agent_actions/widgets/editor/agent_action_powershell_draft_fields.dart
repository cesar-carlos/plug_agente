import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
