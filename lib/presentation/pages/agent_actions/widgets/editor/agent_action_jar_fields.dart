import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
