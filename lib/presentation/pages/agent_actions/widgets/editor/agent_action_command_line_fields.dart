import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
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
