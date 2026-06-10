import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_keys.dart';
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

  static const AgentOperationalProfileResolver _operationalProfileResolver = AgentOperationalProfileResolver();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visibleSections(2)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionExecutionPoliciesSection(
            l10n: l10n,
            enabled: enabled,
            elevatedFeatureEnabled: provider.isElevatedAgentActionsEnabled,
            elevatedRunnerReady:
                provider.isElevatedRunnerConfigured && !provider.isElevatedRunnerDegraded,
            maxAttempts: draft.maxAttempts,
            maxRuntimeMinutesController: draft.executionPolicy.maxRuntimeMinutes,
            killMainProcessOnTimeout: draft.killMainProcessOnTimeout,
            allowRemoteRetry: draft.allowRemoteRetry,
            runElevated: draft.runElevated,
            contextInjectionMode: draft.contextInjectionMode,
            pathChangePolicy: draft.pathChangePolicy,
            runtimeParameterSchemaController: draft.executionPolicy.runtimeParameterSchema,
            callbacks: executionCallbacks,
          ),
        ],
        if (visibleSections(3)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionRuntimePoliciesSection(
            l10n: l10n,
            enabled: enabled,
            currentProfile: _operationalProfileResolver.currentProfile,
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
            callbacks: runtimeCallbacks,
          ),
        ],
        if (visibleSections(4)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionRemotePolicySection(
            l10n: l10n,
            enabled: enabled,
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
        if (visibleSections(5)) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionNotificationPolicySection(
            l10n: l10n,
            enabled: enabled,
            notifyOnSuccess: draft.notifyOnSuccess,
            notifyOnFailure: draft.notifyOnFailure,
            notifyOnTimeout: draft.notifyOnTimeout,
            onNotifyOnSuccessChanged: onNotifyOnSuccessChanged,
            onNotifyOnFailureChanged: onNotifyOnFailureChanged,
            onNotifyOnTimeoutChanged: onNotifyOnTimeoutChanged,
          ),
        ],
      ],
    );
  }
}
