import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';

/// Notification preferences (success/failure/timeout) for an action draft.
///
/// Stateless: the editor owns the boolean state and persists changes via the
/// `on...Changed` callbacks.
class AgentActionNotificationPolicySection extends StatelessWidget {
  const AgentActionNotificationPolicySection({
    required this.l10n,
    required this.enabled,
    required this.notifyOnSuccess,
    required this.notifyOnFailure,
    required this.notifyOnTimeout,
    required this.onNotifyOnSuccessChanged,
    required this.onNotifyOnFailureChanged,
    required this.onNotifyOnTimeoutChanged,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final bool notifyOnSuccess;
  final bool notifyOnFailure;
  final bool notifyOnTimeout;
  final ValueChanged<bool> onNotifyOnSuccessChanged;
  final ValueChanged<bool> onNotifyOnFailureChanged;
  final ValueChanged<bool> onNotifyOnTimeoutChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agentActionsFormNotificationsTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.agentActionsFormNotificationsDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _NotificationCheckbox(
              checked: notifyOnSuccess,
              label: l10n.agentActionsFormNotifyOnSuccess,
              l10n: l10n,
              onChanged: enabled ? onNotifyOnSuccessChanged : null,
            ),
            _NotificationCheckbox(
              checked: notifyOnFailure,
              label: l10n.agentActionsFormNotifyOnFailure,
              l10n: l10n,
              onChanged: enabled ? onNotifyOnFailureChanged : null,
            ),
            _NotificationCheckbox(
              checked: notifyOnTimeout,
              label: l10n.agentActionsFormNotifyOnTimeout,
              l10n: l10n,
              onChanged: enabled ? onNotifyOnTimeoutChanged : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationCheckbox extends StatelessWidget {
  const _NotificationCheckbox({
    required this.checked,
    required this.label,
    required this.l10n,
    required this.onChanged,
  });

  final bool checked;
  final String label;
  final AppLocalizations l10n;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final handler = onChanged;
    return Checkbox(
      checked: checked,
      onChanged: handler == null ? null : (bool? value) => handler(value ?? false),
      content: AgentActionEditorHelpCheckboxLabel(
        label: label,
        helpTitle: l10n.agentActionsHelpNotificationsTitle,
        helpMessage: l10n.agentActionsHelpNotificationsMessage,
      ),
    );
  }
}
