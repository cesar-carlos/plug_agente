import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_section.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionEditorPolicyPanel extends StatelessWidget {
  const AgentActionEditorPolicyPanel({
    required this.l10n,
    required this.provider,
    required this.definition,
    required this.draft,
    required this.enabled,
    required this.showProductionPathAllowlistWarning,
    required this.executionCallbacks,
    required this.runtimeCallbacks,
    required this.onRemoteEnabledChanged,
    required this.onRemoteAdHocChanged,
    required this.onNotifyOnSuccessChanged,
    required this.onNotifyOnFailureChanged,
    required this.onNotifyOnTimeoutChanged,
    required this.visibleSections,
    required this.expandedSections,
    required this.onToggleSection,
    super.key,
  });

  final AppLocalizations l10n;
  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AgentActionDraft draft;
  final bool enabled;
  final bool showProductionPathAllowlistWarning;
  final AgentActionExecutionPoliciesCallbacks executionCallbacks;
  final AgentActionRuntimePoliciesCallbacks runtimeCallbacks;
  final ValueChanged<bool> onRemoteEnabledChanged;
  final ValueChanged<bool> onRemoteAdHocChanged;
  final ValueChanged<bool> onNotifyOnSuccessChanged;
  final ValueChanged<bool> onNotifyOnFailureChanged;
  final ValueChanged<bool> onNotifyOnTimeoutChanged;
  final bool Function(int sectionIndex) visibleSections;
  final Set<int> expandedSections;
  final ValueChanged<int> onToggleSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visibleSections(2))
          AgentActionEditorSection(
            key: const ValueKey('agent_action_section_limits'),
            title: l10n.agentActionsEditorLimits,
            expanded: expandedSections.contains(2),
            onToggle: () => onToggleSection(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExecutionFields(
                  l10n: l10n,
                  provider: provider,
                  draft: draft,
                  enabled: enabled,
                  callbacks: executionCallbacks,
                  showLimits: true,
                ),
                const SizedBox(height: AppSpacing.md),
                _RuntimeFields(
                  l10n: l10n,
                  draft: draft,
                  enabled: enabled,
                  callbacks: runtimeCallbacks,
                  showLifecycle: true,
                  showProductionPathAllowlistWarning: showProductionPathAllowlistWarning,
                ),
              ],
            ),
          ),
        if (visibleSections(3))
          AgentActionEditorSection(
            key: const ValueKey('agent_action_section_advanced'),
            title: l10n.agentActionsEditorAdvanced,
            summary: l10n.agentActionsEditorAdvancedSummary,
            expanded: expandedSections.contains(3),
            onToggle: () => onToggleSection(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExecutionFields(
                  l10n: l10n,
                  provider: provider,
                  draft: draft,
                  enabled: enabled,
                  callbacks: executionCallbacks,
                  showLimits: false,
                ),
                const SizedBox(height: AppSpacing.md),
                _RuntimeFields(
                  l10n: l10n,
                  draft: draft,
                  enabled: enabled,
                  callbacks: runtimeCallbacks,
                  showLifecycle: false,
                  showProductionPathAllowlistWarning: showProductionPathAllowlistWarning,
                ),
                const SizedBox(height: AppSpacing.md),
                if (!draft.draftType.isManualLocalOnly || (definition?.policies.remote.requiresReapproval ?? false))
                  AgentActionRemotePolicySection(
                    l10n: l10n,
                    enabled: enabled && !draft.draftType.isManualLocalOnly,
                    remoteFeatureEnabled: provider.isRemoteAgentActionsEnabled,
                    remoteAdHocFeatureEnabled: provider.isRemoteAdHocAgentActionsEnabled,
                    remoteEnabled: draft.remoteEnabled,
                    remoteAdHoc: draft.remoteAdHoc,
                    remoteApprovalGranted: draft.remoteApprovalGranted,
                    requiresReapproval: definition?.policies.remote.requiresReapproval ?? false,
                    reapprovalInfoBarKey: AgentActionEditorKeys.remoteReapprovalInfoBar,
                    onRemoteEnabledChanged: onRemoteEnabledChanged,
                    onRemoteAdHocChanged: onRemoteAdHocChanged,
                  ),
              ],
            ),
          ),
        if (visibleSections(4))
          AgentActionEditorSection(
            key: const ValueKey('agent_action_section_notifications'),
            title: l10n.agentActionsFormNotificationsTitle,
            expanded: expandedSections.contains(4),
            onToggle: () => onToggleSection(4),
            child: AgentActionNotificationPolicySection(
              l10n: l10n,
              enabled: enabled,
              notifyOnSuccess: draft.notifyOnSuccess,
              notifyOnFailure: draft.notifyOnFailure,
              notifyOnTimeout: draft.notifyOnTimeout,
              onNotifyOnSuccessChanged: onNotifyOnSuccessChanged,
              onNotifyOnFailureChanged: onNotifyOnFailureChanged,
              onNotifyOnTimeoutChanged: onNotifyOnTimeoutChanged,
            ),
          ),
      ],
    );
  }
}

class _ExecutionFields extends StatelessWidget {
  const _ExecutionFields({
    required this.l10n,
    required this.provider,
    required this.draft,
    required this.enabled,
    required this.callbacks,
    required this.showLimits,
  });
  final AppLocalizations l10n;
  final AgentActionsProvider provider;
  final AgentActionDraft draft;
  final bool enabled;
  final AgentActionExecutionPoliciesCallbacks callbacks;
  final bool showLimits;
  @override
  Widget build(BuildContext context) => AgentActionExecutionPoliciesSection(
    l10n: l10n,
    enabled: enabled,
    elevatedFeatureEnabled: provider.isElevatedAgentActionsEnabled,
    elevatedRunnerReady: provider.isElevatedRunnerConfigured && !provider.isElevatedRunnerDegraded,
    maxAttempts: draft.maxAttempts,
    maxRuntimeMinutesController: draft.executionPolicy.maxRuntimeMinutes,
    stopTimeController: draft.executionPolicy.stopTimeOfDay,
    runtimeInSeconds: draft.runtimeInSeconds,
    supportsProcessTermination: draft.draftType.supportsProcessTermination,
    killMainProcessOnTimeout: draft.killMainProcessOnTimeout,
    allowRemoteRetry: draft.allowRemoteRetry,
    runElevated: draft.runElevated,
    contextInjectionMode: draft.contextInjectionMode,
    pathChangePolicy: draft.pathChangePolicy,
    runtimeParameterSchemaController: draft.executionPolicy.runtimeParameterSchema,
    callbacks: callbacks,
    showLimits: showLimits,
    showAdvanced: !showLimits,
    supportsRemoteExecution: !draft.draftType.isManualLocalOnly,
  );
}

class _RuntimeFields extends StatelessWidget {
  const _RuntimeFields({
    required this.l10n,
    required this.draft,
    required this.enabled,
    required this.callbacks,
    required this.showLifecycle,
    required this.showProductionPathAllowlistWarning,
  });
  final AppLocalizations l10n;
  final AgentActionDraft draft;
  final bool enabled;
  final AgentActionRuntimePoliciesCallbacks callbacks;
  final bool showLifecycle;
  final bool showProductionPathAllowlistWarning;
  @override
  Widget build(BuildContext context) => AgentActionRuntimePoliciesSection(
    l10n: l10n,
    enabled: enabled,
    currentProfile: const AgentOperationalProfileResolver().currentProfile,
    allowedProfilesController: draft.executionPolicy.allowedProfiles,
    allowedEnvironmentVariableNamesController: draft.executionPolicy.allowedEnvironmentVariableNames,
    environmentVariablesController: draft.executionPolicy.environmentVariables,
    maxConcurrentController: draft.executionPolicy.maxConcurrent,
    maxQueuedController: draft.executionPolicy.maxQueued,
    concurrencyBehavior: draft.concurrencyBehavior,
    allowedWorkingDirectoriesController: draft.executionPolicy.allowedWorkingDirectories,
    allowedContextDirectoriesController: draft.executionPolicy.allowedContextDirectories,
    showProductionPathAllowlistWarning: showProductionPathAllowlistWarning,
    capturesProcessOutput: draft.capturesProcessOutput(),
    processWindowMode: draft.processWindowMode,
    captureStdout: draft.captureStdout,
    captureStderr: draft.captureStderr,
    redactBeforePersisting: draft.redactBeforePersisting,
    stdoutEncodingMode: draft.stdoutEncodingMode,
    stderrEncodingMode: draft.stderrEncodingMode,
    acceptedExitCodesController: draft.executionPolicy.acceptedExitCodes,
    onAppExit: draft.onAppExit,
    waitBeforeKillSecondsController: draft.executionPolicy.waitBeforeKillSeconds,
    callbacks: callbacks,
    showAdvanced: !showLifecycle,
    showLifecycle: showLifecycle,
  );
}
