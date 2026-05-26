import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// Whether the in-app editor can fully model a given action type.
///
/// Returning `false` here is what surfaces the "unsupported type" risk and
/// disables the edit affordance in the list. Use an exhaustive switch so that
/// adding a new [AgentActionType] forces a compile-time decision instead of
/// silently being treated as non-editable.
bool isAgentActionTypeEditableInUi(AgentActionType type) {
  return switch (type) {
    AgentActionType.commandLine ||
    AgentActionType.executable ||
    AgentActionType.script ||
    AgentActionType.jar ||
    AgentActionType.email ||
    AgentActionType.comObject ||
    AgentActionType.developer => true,
  };
}

class AgentActionRiskDescriptor {
  const AgentActionRiskDescriptor({
    required this.label,
    this.isWarning = false,
  });

  final String label;
  final bool isWarning;
}

List<AgentActionRiskDescriptor> collectAgentActionRiskDescriptors({
  required AgentActionDefinition definition,
  required AppLocalizations l10n,
  Iterable<AgentActionTrigger> triggers = const <AgentActionTrigger>[],
  bool runnerUnavailable = false,
  bool editorUnsupported = false,
  bool needsValidation = false,
  Set<String> secretPlaceholderNames = const <String>{},
}) {
  final descriptors = <AgentActionRiskDescriptor>[];
  final remote = definition.policies.remote;

  if (editorUnsupported) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskUnsupportedType,
        isWarning: true,
      ),
    );
  }
  if (needsValidation) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskNeedsValidation,
        isWarning: true,
      ),
    );
  }
  if (secretPlaceholderNames.isNotEmpty) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskSecretPlaceholders,
        isWarning: true,
      ),
    );
  }
  if (runnerUnavailable) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskRunnerUnavailable,
        isWarning: true,
      ),
    );
  }
  if (definition.policies.elevated.runElevated) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskElevated,
        isWarning: true,
      ),
    );
  }
  if (remote.isEnabled) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskRemote,
        isWarning: true,
      ),
    );
  }
  if (remote.allowAdHoc) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskRemoteAdHoc,
        isWarning: true,
      ),
    );
  }
  if (remote.requiresReapproval) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskRemoteReapproval,
        isWarning: true,
      ),
    );
  }
  if (triggers.any(
    (AgentActionTrigger trigger) => trigger.type == AgentActionTriggerType.appClose && trigger.isEnabled,
  )) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskAppCloseTrigger,
        isWarning: true,
      ),
    );
  }
  if (!definition.policies.capture.redactBeforePersisting) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskSensitiveOutput,
        isWarning: true,
      ),
    );
  }
  if (definition.policies.lifecycle.onAppExit == AgentActionOnAppExitBehavior.leaveRunning) {
    descriptors.add(
      AgentActionRiskDescriptor(
        label: l10n.agentActionsRiskLeaveProcessRunning,
        isWarning: true,
      ),
    );
  }

  return descriptors;
}

class AgentActionRiskChips extends StatelessWidget {
  const AgentActionRiskChips({
    required this.descriptors,
    super.key,
  });

  final List<AgentActionRiskDescriptor> descriptors;

  @override
  Widget build(BuildContext context) {
    if (descriptors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: descriptors
          .map(
            (AgentActionRiskDescriptor descriptor) => _AgentActionRiskChip(descriptor: descriptor),
          )
          .toList(growable: false),
    );
  }
}

class _AgentActionRiskChip extends StatelessWidget {
  const _AgentActionRiskChip({
    required this.descriptor,
  });

  final AgentActionRiskDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final color = descriptor.isWarning ? AppColors.warning : FluentTheme.of(context).resources.textFillColorSecondary;
    final icon = descriptor.isWarning ? FluentIcons.warning : FluentIcons.info;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: descriptor.isWarning ? Border.all(color: color.withValues(alpha: 0.45)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              descriptor.label,
              style: context.captionText.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
