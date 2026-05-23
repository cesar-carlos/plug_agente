import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_confirmations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_test_preview.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_triggers_section.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_secrets_section.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';

class AgentActionSelectedDetailContent extends StatelessWidget {
  const AgentActionSelectedDetailContent({
    required this.provider,
    required this.l10n,
    required this.definition,
    required this.lastTestCanRun,
    required this.onEditAction,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionDefinition definition;
  final bool lastTestCanRun;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(agentActionDefinitionIconFor(definition), size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(definition.name, style: context.sectionTitle)),
            Text(agentActionStateLabel(definition.state, l10n), style: context.bodyMuted),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: l10n.ctButtonEdit,
              child: Semantics(
                button: true,
                label: l10n.ctButtonEdit,
                child: IconButton(
                  icon: const Icon(FluentIcons.edit),
                  onPressed: isAgentActionTypeEditableInUi(definition.type) ? () => onEditAction(definition) : null,
                ),
              ),
            ),
            Tooltip(
              message: l10n.agentActionsDeleteSelected,
              child: Semantics(
                button: true,
                label: l10n.agentActionsDeleteSelected,
                child: IconButton(
                  icon: provider.isDeleting
                      ? const SizedBox.square(
                          dimension: 14,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.delete),
                  onPressed: provider.canDeleteSelected
                      ? () {
                          unawaited(
                            confirmAgentActionDelete(
                              context,
                              provider,
                              definition,
                              l10n,
                            ),
                          );
                        }
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...buildAgentActionDangerousCommandRunGuidance(
          provider: provider,
          definition: definition,
          l10n: l10n,
        ),
        if (provider.lastTestedActionId == definition.id) ...[
          InfoBar(
            title: Text(l10n.agentActionsTestSuccessTitle),
            content: Text(
              lastTestCanRun ? l10n.agentActionsTestCanRunMessage : l10n.agentActionsTestValidButInactiveMessage,
            ),
            severity: lastTestCanRun ? InfoBarSeverity.success : InfoBarSeverity.info,
            isLong: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          AgentActionTestPreview(
            provider: provider,
            l10n: l10n,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            AgentActionDetailPill(text: agentActionDefinitionTypeLabel(definition, l10n)),
            AgentActionDetailPill(text: definition.id),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AgentActionRiskChips(
          key: ValueKey<String>('agent_action_risk_chips_${definition.id}'),
          descriptors: collectAgentActionRiskDescriptors(
            definition: definition,
            l10n: l10n,
            runnerUnavailable: provider.isActionTypeUnavailable(definition.type),
            editorUnsupported: !isAgentActionTypeEditableInUi(definition.type),
            needsValidation: definition.state == AgentActionState.needsValidation,
            secretPlaceholderNames: provider.selectedSecretPlaceholderNames,
            triggers: provider.triggers,
          ),
        ),
        if (definition.state == AgentActionState.needsValidation) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsNeedsValidationTitle),
            content: Text(
              provider.isPreflightValidForDefinition(definition)
                  ? l10n.agentActionsPreflightReadyForActivation
                  : l10n.agentActionsNeedsValidationMessage,
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        if (!isAgentActionTypeEditableInUi(definition.type)) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsValidationTitle),
            content: Text(l10n.agentActionsFormUnsupportedType),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        if (provider.isActionSecretStoreAvailable && provider.selectedSecretPlaceholderNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AgentActionSecretsSection(
            key: ValueKey<String>('agent_action_secrets_${definition.id}'),
            provider: provider,
            l10n: l10n,
          ),
        ] else ...[
          if (provider.selectedSecretPlaceholderNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsSecretPlaceholdersTitle),
              content: Text(
                l10n.agentActionsSecretPlaceholdersMessage(
                  provider.selectedSecretPlaceholderNames.join(', '),
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
          if (provider.selectedMissingSecretNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsMissingSecretsTitle),
              content: Text(
                l10n.agentActionsMissingSecretsMessage(
                  provider.selectedMissingSecretNames.join(', '),
                ),
              ),
              severity: InfoBarSeverity.error,
              isLong: true,
            ),
          ],
        ],
        if (provider.secretOperationErrorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsSecretOperationErrorTitle),
            content: SelectableText(provider.secretOperationErrorMessage!),
            severity: InfoBarSeverity.error,
            isLong: true,
          ),
        ],
        if (provider.isActionTypeUnavailable(definition.type)) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: Text(l10n.agentActionsActionTypeUnavailableTitle),
            content: Text(
              l10n.agentActionsActionTypeUnavailableMessage(
                agentActionDefinitionTypeLabel(definition, l10n),
              ),
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(l10n.agentActionsTriggersTitle, style: context.sectionTitle),
            ),
            Button(
              onPressed: provider.canManageTriggers && !provider.isSavingTrigger
                  ? () {
                      provider.clearTriggerOperationError();
                      unawaited(
                        showAgentActionTriggerSaveDialog(
                          context: context,
                          provider: provider,
                          l10n: l10n,
                          actionId: definition.id,
                        ),
                      );
                    }
                  : null,
              child: Text(l10n.agentActionsTriggerAdd),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AgentActionTriggersSection(
          provider: provider,
          l10n: l10n,
          actionId: definition.id,
        ),
      ],
    );
  }
}

class AgentActionDetailPill extends StatelessWidget {
  const AgentActionDetailPill({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: context.captionText),
    );
  }
}
