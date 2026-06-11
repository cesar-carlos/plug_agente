import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
