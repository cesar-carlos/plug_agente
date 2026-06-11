import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';

/// Remote execution policy controls (enable remote, allow ad-hoc) plus the
/// feature-disabled and reapproval info bars for an action draft.
class AgentActionRemotePolicySection extends StatelessWidget {
  const AgentActionRemotePolicySection({
    required this.l10n,
    required this.enabled,
    required this.remoteFeatureEnabled,
    required this.remoteAdHocFeatureEnabled,
    required this.remoteEnabled,
    required this.remoteAdHoc,
    required this.remoteApprovalGranted,
    required this.requiresReapproval,
    required this.reapprovalInfoBarKey,
    required this.onRemoteEnabledChanged,
    required this.onRemoteAdHocChanged,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final bool remoteFeatureEnabled;
  final bool remoteAdHocFeatureEnabled;
  final bool remoteEnabled;
  final bool remoteAdHoc;
  final bool remoteApprovalGranted;
  final bool requiresReapproval;
  final Key reapprovalInfoBarKey;
  final ValueChanged<bool> onRemoteEnabledChanged;
  final ValueChanged<bool> onRemoteAdHocChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agentActionsFormRemotePoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.agentActionsFormRemotePoliciesDescription,
          style: context.bodyMuted,
        ),
        if (!remoteFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsFormRemoteFeatureDisabledTitle),
            content: Text(l10n.agentActionsFormRemoteFeatureDisabledMessage),
            isLong: true,
          ),
        ] else if (!remoteAdHocFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsFormRemoteAdHocFeatureDisabledTitle),
            content: Text(l10n.agentActionsFormRemoteAdHocFeatureDisabledMessage),
            isLong: true,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: remoteEnabled,
              onChanged: !enabled ? null : (bool? value) => onRemoteEnabledChanged(value ?? false),
              content: AgentActionEditorHelpCheckboxLabel(
                label: l10n.agentActionsFormRemoteExecutionEnabled,
                helpTitle: l10n.agentActionsHelpRemoteExecutionTitle,
                helpMessage: l10n.agentActionsHelpRemoteExecutionMessage,
              ),
            ),
            Checkbox(
              checked: remoteAdHoc,
              onChanged: !enabled || !remoteEnabled || !remoteAdHocFeatureEnabled
                  ? null
                  : (bool? value) => onRemoteAdHocChanged(value ?? false),
              content: AgentActionEditorHelpCheckboxLabel(
                label: l10n.agentActionsFormRemoteAdHocEnabled,
                helpTitle: l10n.agentActionsHelpRemoteAdHocTitle,
                helpMessage: l10n.agentActionsHelpRemoteAdHocMessage,
              ),
            ),
          ],
        ),
        if (requiresReapproval) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            key: reapprovalInfoBarKey,
            title: Text(l10n.agentActionsFormRemoteReapprovalRequiredTitle),
            content: Text(l10n.agentActionsFormRemoteReapprovalRequiredMessage),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ] else if (remoteEnabled && remoteApprovalGranted) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.agentActionsFormRemoteApprovedHint,
            style: context.bodyMuted,
          ),
        ],
      ],
    );
  }
}
