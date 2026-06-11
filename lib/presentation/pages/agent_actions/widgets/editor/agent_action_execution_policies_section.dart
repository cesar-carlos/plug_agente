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
