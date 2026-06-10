import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class AgentActionEditorSaveButton extends StatelessWidget {
  const AgentActionEditorSaveButton({
    required this.l10n,
    required this.saving,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final AppLocalizations l10n;
  final bool saving;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (saving)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.save),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsFormSave),
          ],
        ),
      ),
    );
  }
}
