import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

/// Warning payload for modal feedback in the action editor dialog.
class AgentActionEditorDialogWarning {
  const AgentActionEditorDialogWarning({
    required this.key,
    required this.title,
    required this.message,
  });

  final String key;
  final String title;
  final String message;
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
    this.showInlineFeedback = true,
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
  final bool showInlineFeedback;

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
          reserveHelpAffordance: true,
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

        final inlinePreflight = showInlineFeedback ? preflightInfoBar : const SizedBox.shrink();

        if (stackFields) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nameField,
              const SizedBox(height: AppSpacing.sm),
              typeField,
              const SizedBox(height: AppSpacing.sm),
              stateField,
              inlinePreflight,
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
                Expanded(child: typeField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: stateField),
              ],
            ),
            inlinePreflight,
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

  static AgentActionEditorDialogWarning? resolveWarning(
    AgentActionPreflightGateState state,
    AppLocalizations l10n,
  ) {
    if (state.canSelectActiveState) {
      return null;
    }

    final isExpired = state.hasDefinition && !state.isDraftModifiedSinceLoad && state.isPreflightExpired;
    return AgentActionEditorDialogWarning(
      key: 'preflight_gate',
      title: isExpired ? l10n.agentActionsPreflightExpiredTitle : l10n.agentActionsPreflightRequiredTitle,
      message: isExpired ? l10n.agentActionsPreflightExpiredForActive : l10n.agentActionsPreflightRequiredForActive,
    );
  }

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
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          l10n.agentActionsPreflightExpiresAt(
            DateFormat.yMMMd().add_jm().format(expiresAt.toLocal()),
          ),
          style: context.bodyMuted,
        ),
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
            isExpired ? l10n.agentActionsPreflightExpiredForActive : l10n.agentActionsPreflightRequiredForActive,
          ),
          severity: InfoBarSeverity.warning,
          isLong: true,
        ),
      ],
    );
  }
}
