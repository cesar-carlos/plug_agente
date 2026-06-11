import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
