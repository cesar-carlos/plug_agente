import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_help_button.dart';

class AgentActionEditorPathPickerButton extends StatelessWidget {
  const AgentActionEditorPathPickerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 14),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class AgentActionEditorDeveloperPathShortcuts extends StatelessWidget {
  const AgentActionEditorDeveloperPathShortcuts({
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
    super.key,
  });

  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        Button(
          onPressed: onPrimaryPressed,
          child: Text(primaryLabel),
        ),
        if (secondaryLabel != null)
          Button(
            onPressed: onSecondaryPressed,
            child: Text(secondaryLabel!),
          ),
      ],
    );
  }
}

class AgentActionEditorDeveloperHintData {
  const AgentActionEditorDeveloperHintData._({
    required this.message,
    required this.isWarning,
  });

  const AgentActionEditorDeveloperHintData.info(String message) : this._(message: message, isWarning: false);

  const AgentActionEditorDeveloperHintData.warning(String message) : this._(message: message, isWarning: true);

  final String message;
  final bool isWarning;
}

class AgentActionEditorDeveloperHintsWrap extends StatelessWidget {
  const AgentActionEditorDeveloperHintsWrap({
    required this.hints,
    super.key,
  });

  final List<AgentActionEditorDeveloperHintData> hints;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: hints
          .map(
            (hint) => _AgentActionEditorDeveloperHintChip(hint: hint),
          )
          .toList(growable: false),
    );
  }
}

class _AgentActionEditorDeveloperHintChip extends StatelessWidget {
  const _AgentActionEditorDeveloperHintChip({
    required this.hint,
  });

  final AgentActionEditorDeveloperHintData hint;

  @override
  Widget build(BuildContext context) {
    final color = hint.isWarning ? AppColors.warning : FluentTheme.of(context).resources.textFillColorSecondary;
    final icon = hint.isWarning ? FluentIcons.warning : FluentIcons.info;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            hint.message,
            style: context.captionText.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class AgentActionEditorHelpCheckboxLabel extends StatelessWidget {
  const AgentActionEditorHelpCheckboxLabel({
    required this.label,
    required this.helpTitle,
    required this.helpMessage,
    super.key,
  });

  final String label;
  final String helpTitle;
  final String helpMessage;

  String get _helpKeyToken {
    var token = label.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    while (token.startsWith('_')) {
      token = token.substring(1);
    }
    while (token.endsWith('_')) {
      token = token.substring(0, token.length - 1);
    }
    return token;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label),
        AppHelpButton(
          key: ValueKey<String>('app_help_button_$_helpKeyToken'),
          title: helpTitle,
          message: helpMessage,
          semanticLabel: '$label. $helpTitle',
        ),
      ],
    );
  }
}

String agentActionEditorTypeLabel(AgentActionType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionType.commandLine => l10n.agentActionsTypeCommandLine,
    AgentActionType.executable => l10n.agentActionsTypeExecutable,
    AgentActionType.script => l10n.agentActionsTypeScript,
    AgentActionType.jar => l10n.agentActionsTypeJar,
    AgentActionType.email => l10n.agentActionsTypeEmail,
    AgentActionType.comObject => l10n.agentActionsTypeComObject,
    AgentActionType.developer => l10n.agentActionsTypeDeveloper,
  };
}

String agentActionEditorStateLabel(AgentActionState state, AppLocalizations l10n) {
  return switch (state) {
    AgentActionState.active => l10n.agentActionsStateActive,
    AgentActionState.paused => l10n.agentActionsStatePaused,
    AgentActionState.disabled => l10n.agentActionsStateDisabled,
    AgentActionState.needsValidation => l10n.agentActionsStateNeedsValidation,
  };
}

