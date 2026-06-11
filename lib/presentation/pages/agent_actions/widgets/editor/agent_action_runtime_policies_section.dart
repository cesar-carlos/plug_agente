import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

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
