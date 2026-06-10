import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class AgentActionEditorFormHeader extends StatelessWidget {
  const AgentActionEditorFormHeader({
    required this.l10n,
    required this.title,
    required this.showChrome,
    required this.saving,
    required this.canSaveAction,
    required this.validationMessage,
    required this.onClearValidation,
    required this.onNewDraft,
    super.key,
  });

  final AppLocalizations l10n;
  final String title;
  final bool showChrome;
  final bool saving;
  final bool canSaveAction;
  final String? validationMessage;
  final VoidCallback onClearValidation;
  final VoidCallback onNewDraft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showChrome) ...[
          const Divider(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (showChrome && validationMessage != null && validationMessage!.isNotEmpty) ...[
          InfoBar(
            key: const ValueKey<String>('agent_action_editor_validation_message'),
            title: Text(l10n.agentActionsValidationTitle),
            content: Text(validationMessage!),
            severity: InfoBarSeverity.warning,
            isLong: true,
            action: Button(
              onPressed: onClearValidation,
              child: Text(l10n.btnClose),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: context.sectionTitle,
              ),
            ),
            if (showChrome)
              Button(
                onPressed: saving || !canSaveAction ? null : onNewDraft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.add),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l10n.agentActionsFormNew),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
