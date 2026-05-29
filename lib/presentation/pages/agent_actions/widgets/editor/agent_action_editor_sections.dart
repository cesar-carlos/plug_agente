import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

/// Change handlers for [AgentActionExecutionPoliciesSection]. Grouped so the
/// section widget keeps a small, cohesive constructor instead of a long list of
/// loose callbacks.
class AgentActionExecutionPoliciesCallbacks {
  const AgentActionExecutionPoliciesCallbacks({
    required this.onMaxAttemptsChanged,
    required this.onMaxRuntimeMinutesChanged,
    required this.onKillOnTimeoutChanged,
    required this.onAllowRemoteRetryChanged,
    required this.onRunElevatedChanged,
    required this.onContextInjectionModeChanged,
    required this.onPathChangePolicyChanged,
  });

  final ValueChanged<int> onMaxAttemptsChanged;
  final ValueChanged<String> onMaxRuntimeMinutesChanged;
  final ValueChanged<bool> onKillOnTimeoutChanged;
  final ValueChanged<bool> onAllowRemoteRetryChanged;
  final ValueChanged<bool> onRunElevatedChanged;
  final ValueChanged<AgentActionContextInjectionMode> onContextInjectionModeChanged;
  final ValueChanged<AgentActionPathChangePolicy> onPathChangePolicyChanged;
}

/// Execution policies (retry/timeout/elevation/context/path) for an action
/// draft. Stateless: the editor owns the values and persists via [callbacks].
class AgentActionExecutionPoliciesSection extends StatelessWidget {
  const AgentActionExecutionPoliciesSection({
    required this.l10n,
    required this.enabled,
    required this.elevatedFeatureEnabled,
    required this.elevatedRunnerReady,
    required this.maxAttempts,
    required this.maxRuntimeMinutesController,
    required this.killMainProcessOnTimeout,
    required this.allowRemoteRetry,
    required this.runElevated,
    required this.contextInjectionMode,
    required this.pathChangePolicy,
    required this.runtimeParameterSchemaController,
    required this.callbacks,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final bool elevatedFeatureEnabled;
  final bool elevatedRunnerReady;
  final int maxAttempts;
  final TextEditingController maxRuntimeMinutesController;
  final bool killMainProcessOnTimeout;
  final bool allowRemoteRetry;
  final bool runElevated;
  final AgentActionContextInjectionMode contextInjectionMode;
  final AgentActionPathChangePolicy pathChangePolicy;
  final TextEditingController runtimeParameterSchemaController;
  final AgentActionExecutionPoliciesCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agentActionsFormExecutionPoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.agentActionsFormExecutionPoliciesDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: AppDropdown<int>(
                label: l10n.agentActionsFormMaxAttempts,
                helpTitle: l10n.agentActionsHelpMaxAttemptsTitle,
                helpMessage: l10n.agentActionsHelpMaxAttemptsMessage,
                value: maxAttempts,
                items: List<ComboBoxItem<int>>.generate(
                  5,
                  (int index) {
                    final attempts = index + 1;
                    return ComboBoxItem<int>(
                      value: attempts,
                      child: Text('$attempts'),
                    );
                  },
                  growable: false,
                ),
                onChanged: enabled
                    ? (int? value) {
                        if (value == null) {
                          return;
                        }
                        callbacks.onMaxAttemptsChanged(value);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                label: l10n.agentActionsFormMaxRuntimeMinutes,
                helpTitle: l10n.agentActionsHelpTimeoutTitle,
                helpMessage: l10n.agentActionsHelpTimeoutMessage,
                controller: maxRuntimeMinutesController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: callbacks.onMaxRuntimeMinutesChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              checked: killMainProcessOnTimeout,
              onChanged: enabled ? (bool? value) => callbacks.onKillOnTimeoutChanged(value ?? true) : null,
              content: AgentActionEditorHelpCheckboxLabel(
                label: l10n.agentActionsFormKillOnTimeout,
                helpTitle: l10n.agentActionsHelpKillOnTimeoutTitle,
                helpMessage: l10n.agentActionsHelpKillOnTimeoutMessage,
              ),
            ),
            Checkbox(
              checked: allowRemoteRetry,
              onChanged: enabled ? (bool? value) => callbacks.onAllowRemoteRetryChanged(value ?? false) : null,
              content: AgentActionEditorHelpCheckboxLabel(
                label: l10n.agentActionsFormAllowRemoteRetry,
                helpTitle: l10n.agentActionsHelpRemoteRetryTitle,
                helpMessage: l10n.agentActionsHelpRemoteRetryMessage,
              ),
            ),
            if (elevatedFeatureEnabled)
              Checkbox(
                checked: runElevated,
                onChanged: enabled && elevatedRunnerReady
                    ? (bool? value) => callbacks.onRunElevatedChanged(value ?? false)
                    : null,
                content: AgentActionEditorHelpCheckboxLabel(
                  label: l10n.agentActionsFormRunElevated,
                  helpTitle: l10n.agentActionsHelpRunElevatedTitle,
                  helpMessage: l10n.agentActionsHelpRunElevatedMessage,
                ),
              ),
          ],
        ),
        if (elevatedFeatureEnabled) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.agentActionsFormRunElevatedHint,
            style: context.bodyMuted,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppDropdown<AgentActionContextInjectionMode>(
          label: l10n.agentActionsFormContextInjectionMode,
          helpTitle: l10n.agentActionsHelpContextInjectionTitle,
          helpMessage: l10n.agentActionsHelpContextInjectionMessage,
          value: contextInjectionMode,
          items: [
            ComboBoxItem(
              value: AgentActionContextInjectionMode.argument,
              child: Text(l10n.agentActionsFormContextInjectionArgument),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.file,
              child: Text(l10n.agentActionsFormContextInjectionFile),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.environment,
              child: Text(l10n.agentActionsFormContextInjectionEnvironment),
            ),
            ComboBoxItem(
              value: AgentActionContextInjectionMode.stdin,
              child: Text(l10n.agentActionsFormContextInjectionStdin),
            ),
          ],
          onChanged: enabled
              ? (AgentActionContextInjectionMode? value) {
                  if (value == null) {
                    return;
                  }
                  callbacks.onContextInjectionModeChanged(value);
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<AgentActionPathChangePolicy>(
          label: l10n.agentActionsFormPathChangePolicy,
          helpTitle: l10n.agentActionsHelpPathChangePolicyTitle,
          helpMessage: l10n.agentActionsHelpPathChangePolicyMessage,
          value: pathChangePolicy,
          items: [
            ComboBoxItem(
              value: AgentActionPathChangePolicy.failIfChanged,
              child: Text(l10n.agentActionsFormPathChangePolicyFail),
            ),
            ComboBoxItem(
              value: AgentActionPathChangePolicy.warnIfChanged,
              child: Text(l10n.agentActionsFormPathChangePolicyWarn),
            ),
            ComboBoxItem(
              value: AgentActionPathChangePolicy.allowChanged,
              child: Text(l10n.agentActionsFormPathChangePolicyAllow),
            ),
          ],
          onChanged: enabled
              ? (AgentActionPathChangePolicy? value) {
                  if (value == null) {
                    return;
                  }
                  callbacks.onPathChangePolicyChanged(value);
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormRuntimeParameterSchema,
          helpTitle: l10n.agentActionsHelpRuntimeSchemaTitle,
          helpMessage: l10n.agentActionsHelpRuntimeSchemaMessage,
          controller: runtimeParameterSchemaController,
          enabled: enabled,
          maxLines: 6,
          hint: l10n.agentActionsFormRuntimeParameterSchemaHint,
        ),
      ],
    );
  }
}

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
