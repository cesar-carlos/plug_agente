import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
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

/// Change handlers for [AgentActionRuntimePoliciesSection]. Grouped to keep the
/// section's constructor cohesive instead of a long list of loose callbacks.
class AgentActionRuntimePoliciesCallbacks {
  const AgentActionRuntimePoliciesCallbacks({
    required this.onConcurrencyBehaviorChanged,
    required this.onProcessWindowModeChanged,
    required this.onCaptureStdoutChanged,
    required this.onCaptureStderrChanged,
    required this.onRedactBeforePersistingChanged,
    required this.onStdoutEncodingModeChanged,
    required this.onStderrEncodingModeChanged,
    required this.onOnAppExitChanged,
  });

  final ValueChanged<AgentActionConcurrencyBehavior> onConcurrencyBehaviorChanged;
  final ValueChanged<AgentActionProcessWindowMode> onProcessWindowModeChanged;
  final ValueChanged<bool> onCaptureStdoutChanged;
  final ValueChanged<bool> onCaptureStderrChanged;
  final ValueChanged<bool> onRedactBeforePersistingChanged;
  final ValueChanged<AgentActionOutputEncodingMode> onStdoutEncodingModeChanged;
  final ValueChanged<AgentActionOutputEncodingMode> onStderrEncodingModeChanged;
  final ValueChanged<AgentActionOnAppExitBehavior> onOnAppExitChanged;
}

/// Runtime policies for an action draft: operational profiles, environment,
/// queue limits, path allowlists, output capture/window, output encoding and
/// exit-code handling. Stateless; the editor owns the controllers/values and
/// persists changes via [callbacks].
class AgentActionRuntimePoliciesSection extends StatelessWidget {
  const AgentActionRuntimePoliciesSection({
    required this.l10n,
    required this.enabled,
    required this.currentProfile,
    required this.allowedProfilesController,
    required this.allowedEnvironmentVariableNamesController,
    required this.environmentVariablesController,
    required this.maxConcurrentController,
    required this.maxQueuedController,
    required this.concurrencyBehavior,
    required this.allowedWorkingDirectoriesController,
    required this.allowedContextDirectoriesController,
    required this.showProductionPathAllowlistWarning,
    required this.capturesProcessOutput,
    required this.processWindowMode,
    required this.captureStdout,
    required this.captureStderr,
    required this.redactBeforePersisting,
    required this.stdoutEncodingMode,
    required this.stderrEncodingMode,
    required this.acceptedExitCodesController,
    required this.onAppExit,
    required this.callbacks,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final String? currentProfile;
  final TextEditingController allowedProfilesController;
  final TextEditingController allowedEnvironmentVariableNamesController;
  final TextEditingController environmentVariablesController;
  final TextEditingController maxConcurrentController;
  final TextEditingController maxQueuedController;
  final AgentActionConcurrencyBehavior concurrencyBehavior;
  final TextEditingController allowedWorkingDirectoriesController;
  final TextEditingController allowedContextDirectoriesController;
  final bool showProductionPathAllowlistWarning;
  final bool capturesProcessOutput;
  final AgentActionProcessWindowMode processWindowMode;
  final bool captureStdout;
  final bool captureStderr;
  final bool redactBeforePersisting;
  final AgentActionOutputEncodingMode stdoutEncodingMode;
  final AgentActionOutputEncodingMode stderrEncodingMode;
  final TextEditingController acceptedExitCodesController;
  final AgentActionOnAppExitBehavior onAppExit;
  final AgentActionRuntimePoliciesCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agentActionsFormRuntimePoliciesTitle, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.agentActionsFormRuntimePoliciesDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          title: Text(
            currentProfile == null
                ? l10n.agentActionsFormCurrentOperationalProfileUnset
                : l10n.agentActionsFormCurrentOperationalProfile(currentProfile!),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormAllowedProfiles,
          helpTitle: l10n.agentActionsHelpAllowedProfilesTitle,
          helpMessage: l10n.agentActionsHelpAllowedProfilesMessage,
          controller: allowedProfilesController,
          enabled: enabled,
          hint: l10n.agentActionsFormAllowedProfilesHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormAllowedEnvironmentVariableNames,
          helpTitle: l10n.agentActionsHelpAllowedEnvironmentVariablesTitle,
          helpMessage: l10n.agentActionsHelpAllowedEnvironmentVariablesMessage,
          controller: allowedEnvironmentVariableNamesController,
          enabled: enabled,
          hint: l10n.agentActionsFormAllowedEnvironmentVariableNamesHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormEnvironmentVariables,
          helpTitle: l10n.agentActionsHelpEnvironmentVariablesTitle,
          helpMessage: l10n.agentActionsHelpEnvironmentVariablesMessage,
          controller: environmentVariablesController,
          enabled: enabled,
          maxLines: 6,
          hint: l10n.agentActionsFormEnvironmentVariablesHint,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.agentActionsFormQueuePolicyDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final maxConcurrentField = AppTextField(
              label: l10n.agentActionsFormMaxConcurrent,
              helpTitle: l10n.agentActionsHelpQueueTitle,
              helpMessage: l10n.agentActionsHelpQueueMessage,
              controller: maxConcurrentController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            );
            final maxQueuedField = AppTextField(
              label: l10n.agentActionsFormMaxQueued,
              helpTitle: l10n.agentActionsHelpQueueTitle,
              helpMessage: l10n.agentActionsHelpQueueMessage,
              controller: maxQueuedController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  maxConcurrentField,
                  const SizedBox(height: AppSpacing.sm),
                  maxQueuedField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: maxConcurrentField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: maxQueuedField),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppDropdown<AgentActionConcurrencyBehavior>(
          label: l10n.agentActionsFormConcurrencyBehavior,
          helpTitle: l10n.agentActionsHelpQueueTitle,
          helpMessage: l10n.agentActionsHelpQueueMessage,
          value: concurrencyBehavior,
          items: AgentActionConcurrencyBehavior.values
              .map(
                (AgentActionConcurrencyBehavior behavior) => ComboBoxItem<AgentActionConcurrencyBehavior>(
                  value: behavior,
                  child: Text(agentActionEditorConcurrencyBehaviorLabel(behavior, l10n)),
                ),
              )
              .toList(growable: false),
          onChanged: enabled
              ? (AgentActionConcurrencyBehavior? value) {
                  if (value == null) {
                    return;
                  }
                  callbacks.onConcurrencyBehaviorChanged(value);
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.agentActionsFormPathAllowlistDescription,
          style: context.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormAllowedWorkingDirectories,
          helpTitle: l10n.agentActionsHelpPathAllowlistTitle,
          helpMessage: l10n.agentActionsHelpPathAllowlistMessage,
          controller: allowedWorkingDirectoriesController,
          enabled: enabled,
          maxLines: 3,
          hint: l10n.agentActionsFormPathAllowlistHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: l10n.agentActionsFormAllowedContextDirectories,
          helpTitle: l10n.agentActionsHelpPathAllowlistTitle,
          helpMessage: l10n.agentActionsHelpPathAllowlistMessage,
          controller: allowedContextDirectoriesController,
          enabled: enabled,
          maxLines: 3,
          hint: l10n.agentActionsFormPathAllowlistHint,
          textInputAction: TextInputAction.next,
        ),
        if (showProductionPathAllowlistWarning) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsProductionPathAllowlistRequiredTitle),
            content: Text(l10n.agentActionsProductionPathAllowlistRequiredMessage),
            severity: InfoBarSeverity.error,
            isLong: true,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (capturesProcessOutput) ...[
          AppDropdown<AgentActionProcessWindowMode>(
            label: l10n.agentActionsFormProcessWindowMode,
            helpTitle: l10n.agentActionsHelpProcessWindowTitle,
            helpMessage: l10n.agentActionsHelpProcessWindowMessage,
            value: processWindowMode,
            items: AgentActionProcessWindowMode.values
                .map(
                  (AgentActionProcessWindowMode mode) => ComboBoxItem<AgentActionProcessWindowMode>(
                    value: mode,
                    child: Text(agentActionEditorProcessWindowModeLabel(mode, l10n)),
                  ),
                )
                .toList(growable: false),
            onChanged: enabled
                ? (AgentActionProcessWindowMode? value) {
                    if (value == null) {
                      return;
                    }
                    callbacks.onProcessWindowModeChanged(value);
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.agentActionsFormCapturePolicyDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Checkbox(
                checked: captureStdout,
                onChanged: enabled ? (bool? value) => callbacks.onCaptureStdoutChanged(value ?? true) : null,
                content: AgentActionEditorHelpCheckboxLabel(
                  label: l10n.agentActionsFormCaptureStdout,
                  helpTitle: l10n.agentActionsHelpCaptureTitle,
                  helpMessage: l10n.agentActionsHelpCaptureMessage,
                ),
              ),
              Checkbox(
                checked: captureStderr,
                onChanged: enabled ? (bool? value) => callbacks.onCaptureStderrChanged(value ?? true) : null,
                content: AgentActionEditorHelpCheckboxLabel(
                  label: l10n.agentActionsFormCaptureStderr,
                  helpTitle: l10n.agentActionsHelpCaptureTitle,
                  helpMessage: l10n.agentActionsHelpCaptureMessage,
                ),
              ),
              Checkbox(
                checked: redactBeforePersisting,
                onChanged: enabled ? (bool? value) => callbacks.onRedactBeforePersistingChanged(value ?? true) : null,
                content: AgentActionEditorHelpCheckboxLabel(
                  label: l10n.agentActionsFormRedactBeforePersisting,
                  helpTitle: l10n.agentActionsHelpCaptureTitle,
                  helpMessage: l10n.agentActionsHelpCaptureMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.agentActionsFormOutputEncodingDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDropdown<AgentActionOutputEncodingMode>(
                  label: l10n.agentActionsFormStdoutEncoding,
                  helpTitle: l10n.agentActionsHelpEncodingTitle,
                  helpMessage: l10n.agentActionsHelpEncodingMessage,
                  value: stdoutEncodingMode,
                  items: AgentActionOutputEncodingMode.values
                      .map(
                        (AgentActionOutputEncodingMode mode) => ComboBoxItem<AgentActionOutputEncodingMode>(
                          value: mode,
                          child: Text(agentActionEditorOutputEncodingModeLabel(mode, l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: enabled
                      ? (AgentActionOutputEncodingMode? value) {
                          if (value == null) {
                            return;
                          }
                          callbacks.onStdoutEncodingModeChanged(value);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppDropdown<AgentActionOutputEncodingMode>(
                  label: l10n.agentActionsFormStderrEncoding,
                  helpTitle: l10n.agentActionsHelpEncodingTitle,
                  helpMessage: l10n.agentActionsHelpEncodingMessage,
                  value: stderrEncodingMode,
                  items: AgentActionOutputEncodingMode.values
                      .map(
                        (AgentActionOutputEncodingMode mode) => ComboBoxItem<AgentActionOutputEncodingMode>(
                          value: mode,
                          child: Text(agentActionEditorOutputEncodingModeLabel(mode, l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: enabled
                      ? (AgentActionOutputEncodingMode? value) {
                          if (value == null) {
                            return;
                          }
                          callbacks.onStderrEncodingModeChanged(value);
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stackFields = constraints.maxWidth < 720;
            final exitCodesField = AppTextField(
              label: l10n.agentActionsFormAcceptedExitCodes,
              helpTitle: l10n.agentActionsHelpAcceptedExitCodesTitle,
              helpMessage: l10n.agentActionsHelpAcceptedExitCodesMessage,
              controller: acceptedExitCodesController,
              enabled: enabled,
              hint: l10n.agentActionsFormAcceptedExitCodesHint,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
            );
            final onAppExitField = AppDropdown<AgentActionOnAppExitBehavior>(
              label: l10n.agentActionsFormOnAppExit,
              helpTitle: l10n.agentActionsHelpOnAppExitTitle,
              helpMessage: l10n.agentActionsHelpOnAppExitMessage,
              value: onAppExit,
              items: AgentActionOnAppExitBehavior.values
                  .map(
                    (AgentActionOnAppExitBehavior behavior) => ComboBoxItem<AgentActionOnAppExitBehavior>(
                      value: behavior,
                      child: Text(agentActionEditorOnAppExitLabel(behavior, l10n)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled
                  ? (AgentActionOnAppExitBehavior? value) {
                      if (value == null) {
                        return;
                      }
                      callbacks.onOnAppExitChanged(value);
                    }
                  : null,
            );

            if (stackFields) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  exitCodesField,
                  const SizedBox(height: AppSpacing.sm),
                  onAppExitField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: exitCodesField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 280, child: onAppExitField),
              ],
            );
          },
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

/// Identity row of the editor (name + kind + state) plus the preflight
/// gate info bar. Extracted from the editor's monolithic `build()` so
/// the layout-builder + 3 fields + info bar are testable in isolation
/// and the editor body shrinks to a list of sections.
class AgentActionIdentitySection extends StatelessWidget {
  const AgentActionIdentitySection({
    required this.l10n,
    required this.enabled,
    required this.isEditing,
    required this.actionTypeDisplayController,
    required this.draftKind,
    required this.editableDraftKinds,
    required this.isDraftKindUnavailable,
    required this.draftKindLabel,
    required this.onDraftKindChanged,
    required this.nameController,
    required this.state,
    required this.canSelectActiveState,
    required this.stateLabelForValue,
    required this.onStateChanged,
    required this.preflightInfoBar,
    required this.actionTypeDropdownKey,
    super.key,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final bool isEditing;
  final TextEditingController actionTypeDisplayController;
  final AgentActionDraftKind draftKind;
  final List<AgentActionDraftKind> editableDraftKinds;
  final bool Function(AgentActionDraftKind) isDraftKindUnavailable;
  final String Function(AgentActionDraftKind) draftKindLabel;
  final ValueChanged<AgentActionDraftKind> onDraftKindChanged;
  final TextEditingController nameController;
  final AgentActionState state;
  final bool canSelectActiveState;
  final String Function(AgentActionState) stateLabelForValue;
  final ValueChanged<AgentActionState> onStateChanged;
  final Widget preflightInfoBar;
  final ValueKey<String> actionTypeDropdownKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackFields = constraints.maxWidth < 720;
        final nameField = AppTextField(
          label: l10n.agentActionsFormName,
          controller: nameController,
          enabled: enabled,
          textInputAction: TextInputAction.next,
        );
        final typeField = isEditing
            ? AppTextField(
                key: actionTypeDropdownKey,
                label: l10n.agentActionsFormType,
                helpTitle: l10n.agentActionsHelpTypeTitle,
                helpMessage: l10n.agentActionsHelpTypeMessage,
                controller: actionTypeDisplayController,
                enabled: enabled,
                readOnly: true,
                textInputAction: TextInputAction.next,
              )
            : AppDropdown<AgentActionDraftKind>(
                key: actionTypeDropdownKey,
                label: l10n.agentActionsFormType,
                helpTitle: l10n.agentActionsHelpTypeTitle,
                helpMessage: l10n.agentActionsHelpTypeMessage,
                value: draftKind,
                items: editableDraftKinds
                    .map(
                      (kind) {
                        final unavailable = isDraftKindUnavailable(kind);
                        final label = draftKindLabel(kind);
                        return ComboBoxItem<AgentActionDraftKind>(
                          value: kind,
                          enabled: !unavailable,
                          child: Text(
                            unavailable ? '$label (${l10n.agentActionsRiskRunnerUnavailable})' : label,
                          ),
                        );
                      },
                    )
                    .toList(growable: false),
                onChanged: !enabled
                    ? null
                    : (value) {
                        if (value == null || value == draftKind) {
                          return;
                        }
                        onDraftKindChanged(value);
                      },
              );
        final stateField = AppDropdown<AgentActionState>(
          label: l10n.agentActionsFormState,
          helpTitle: l10n.agentActionsHelpStateTitle,
          helpMessage: l10n.agentActionsHelpStateMessage,
          value: state,
          items: AgentActionState.values
              .map(
                (value) => ComboBoxItem<AgentActionState>(
                  value: value,
                  enabled: value != AgentActionState.active || canSelectActiveState,
                  child: Text(stateLabelForValue(value)),
                ),
              )
              .toList(growable: false),
          onChanged: !enabled
              ? null
              : (value) {
                  if (value == null) return;
                  onStateChanged(value);
                },
        );

        if (stackFields) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nameField,
              const SizedBox(height: AppSpacing.sm),
              typeField,
              const SizedBox(height: AppSpacing.sm),
              stateField,
              preflightInfoBar,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: nameField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 220, child: typeField),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 220, child: stateField),
              ],
            ),
            preflightInfoBar,
          ],
        );
      },
    );
  }
}

/// Snapshot of the preflight gate. Composed from the live provider so
/// the editor does not query timestamps inline in the build method.
class AgentActionPreflightGateState {
  const AgentActionPreflightGateState({
    required this.canSelectActiveState,
    required this.isDraftModifiedSinceLoad,
    required this.hasDefinition,
    required this.preflightExpiresAt,
    required this.isPreflightExpired,
  });

  final bool canSelectActiveState;
  final bool isDraftModifiedSinceLoad;
  final bool hasDefinition;
  final DateTime? preflightExpiresAt;
  final bool isPreflightExpired;
}

/// Info bar shown above the identity row when the preflight gate
/// blocks the active state, when preflight is still valid, or when it
/// has expired. Extracted out of the editor so each branch is testable.
class AgentActionPreflightGateInfoBar extends StatelessWidget {
  const AgentActionPreflightGateInfoBar({
    required this.l10n,
    required this.state,
    super.key,
  });

  final AppLocalizations l10n;
  final AgentActionPreflightGateState state;

  @override
  Widget build(BuildContext context) {
    if (state.canSelectActiveState) {
      if (!state.hasDefinition || state.isDraftModifiedSinceLoad) {
        return const SizedBox.shrink();
      }
      final expiresAt = state.preflightExpiresAt;
      if (expiresAt == null) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsPreflightValidTitle),
            content: Text(
              l10n.agentActionsPreflightExpiresAt(
                DateFormat.yMMMd().add_jm().format(expiresAt.toLocal()),
              ),
            ),
            isLong: true,
          ),
        ],
      );
    }

    final isExpired = state.hasDefinition && !state.isDraftModifiedSinceLoad && state.isPreflightExpired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        InfoBar(
          title: Text(
            isExpired ? l10n.agentActionsPreflightExpiredTitle : l10n.agentActionsPreflightRequiredTitle,
          ),
          content: Text(
            isExpired
                ? l10n.agentActionsPreflightExpiredForActive
                : l10n.agentActionsPreflightRequiredForActive,
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ],
    );
  }
}
