import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionsStatusStrip extends StatelessWidget {
  const AgentActionsStatusStrip({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final statusWidgets = <Widget>[
      if (!provider.isFeatureEnabled)
        InfoBar(
          title: Text(l10n.agentActionsDisabledTitle),
          content: Text(l10n.agentActionsDisabledMessage),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ...buildAgentActionRuntimeSubsystemStatusWidgets(provider, l10n),
      ...buildAgentActionSchedulerOperationalIssueWidgets(provider, l10n),
      ...buildAgentActionComObjectInvocationWarnings(provider, l10n),
      if (provider.errorMessage != null)
        InfoBar(
          title: Text(l10n.agentActionsErrorTitle),
          content: SelectableText(provider.errorMessage!),
          severity: InfoBarSeverity.error,
          isLong: true,
        ),
    ];

    if (statusWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 170),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: statusWidgets.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => statusWidgets[index],
      ),
    );
  }
}

List<Widget> buildAgentActionComObjectInvocationWarnings(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.shouldWarnComObjectHandlersMissing) {
    return const <Widget>[];
  }

  return <Widget>[
    InfoBar(
      key: const ValueKey<String>('agent_actions_com_object_handlers_missing'),
      title: Text(l10n.agentActionsComObjectHandlersMissingTitle),
      content: Text(l10n.agentActionsComObjectHandlersMissingMessage),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    const SizedBox(height: AppSpacing.md),
  ];
}

List<Widget> buildAgentActionSchedulerOperationalIssueWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.isFeatureEnabled) {
    return const <Widget>[];
  }

  final reason = provider.schedulerOperationalIssueReason;
  if (reason == null) {
    return const <Widget>[];
  }

  final message = switch (reason) {
    AgentActionTriggerConstants.schedulerInstanceLockedReason => l10n.agentActionsSchedulerInstanceLockedMessage,
    AgentActionTriggerConstants.schedulerBootstrapFailedReason => l10n.agentActionsSchedulerBootstrapFailedMessage,
    _ => null,
  };
  if (message == null) {
    return const <Widget>[];
  }

  return <Widget>[
    InfoBar(
      key: const ValueKey<String>('agent_actions_scheduler_operational_issue'),
      title: Text(l10n.agentActionsSchedulerOperationalIssueTitle),
      content: Text(message),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    const SizedBox(height: AppSpacing.md),
  ];
}

List<Widget> buildAgentActionRuntimeSubsystemStatusWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.isFeatureEnabled) {
    return const <Widget>[];
  }

  final bar = buildAgentActionRuntimeSubsystemInfoBar(provider, l10n);
  if (bar == null) {
    return const <Widget>[];
  }

  return <Widget>[
    bar,
    const SizedBox(height: AppSpacing.md),
  ];
}

List<Widget> buildAgentActionElevatedRunnerStatusWidgets(AgentActionsProvider provider, AppLocalizations l10n) {
  if (!provider.isElevatedAgentActionsEnabled) {
    return const <Widget>[];
  }

  final widgets = <Widget>[];
  if (provider.isElevatedRunnerDegraded) {
    widgets.add(
      InfoBar(
        title: Text(l10n.agentActionsElevatedRunnerDegradedTitle),
        content: Text(l10n.agentActionsElevatedRunnerDegradedMessage),
        severity: InfoBarSeverity.warning,
        isLong: true,
        action: Button(
          onPressed: provider.isPreparingElevatedRunner
              ? null
              : () {
                  unawaited(provider.prepareElevatedRunner());
                },
          child: Text(
            provider.isPreparingElevatedRunner
                ? l10n.agentActionsElevatedRunnerPreparing
                : l10n.agentActionsElevatedRunnerPrepare,
          ),
        ),
      ),
    );
  } else if (!provider.isElevatedRunnerConfigured) {
    widgets.add(
      InfoBar(
        title: Text(l10n.agentActionsElevatedRunnerNotReadyTitle),
        content: Text(l10n.agentActionsElevatedRunnerNotReadyMessage),
        severity: InfoBarSeverity.warning,
        isLong: true,
        action: Button(
          onPressed: provider.isPreparingElevatedRunner
              ? null
              : () {
                  unawaited(provider.prepareElevatedRunner());
                },
          child: Text(
            provider.isPreparingElevatedRunner
                ? l10n.agentActionsElevatedRunnerPreparing
                : l10n.agentActionsElevatedRunnerPrepare,
          ),
        ),
      ),
    );
  }

  if (widgets.isEmpty) {
    return const <Widget>[];
  }

  return <Widget>[
    ...widgets,
    const SizedBox(height: AppSpacing.md),
  ];
}

Widget? buildAgentActionRuntimeSubsystemInfoBar(AgentActionsProvider provider, AppLocalizations l10n) {
  final snapshot = provider.runtimeSubsystemSnapshot;
  return switch (snapshot.status) {
    AgentActionSubsystemStatus.ready || AgentActionSubsystemStatus.maintenance => null,
    AgentActionSubsystemStatus.starting => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusStartingTitle),
      content: Text(l10n.agentActionsSubsystemStatusStartingMessage),
      isLong: true,
    ),
    AgentActionSubsystemStatus.draining => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusDrainingTitle),
      content: Text(l10n.agentActionsSubsystemStatusDrainingMessage),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    AgentActionSubsystemStatus.degraded => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusDegradedTitle),
      content: Text(
        l10n.agentActionsSubsystemStatusDegradedMessage(
          snapshot.unavailableActionTypes.map((AgentActionType type) => type.name).join(', '),
        ),
      ),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    AgentActionSubsystemStatus.disabled => InfoBar(
      title: Text(l10n.agentActionsSubsystemStatusDisabledTitle),
      content: Text(l10n.agentActionsSubsystemStatusDisabledMessage),
      severity: InfoBarSeverity.error,
      isLong: true,
    ),
  };
}
