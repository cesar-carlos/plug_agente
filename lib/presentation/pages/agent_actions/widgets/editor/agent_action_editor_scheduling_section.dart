import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_copyable_identifier.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionEditorSchedulingSection extends StatefulWidget {
  const AgentActionEditorSchedulingSection({
    required this.provider,
    required this.l10n,
    required this.actionId,
    required this.manualOnly,
    required this.enabled,
    super.key,
  });
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String? actionId;
  final bool manualOnly;
  final bool enabled;
  @override
  State<AgentActionEditorSchedulingSection> createState() => _AgentActionEditorSchedulingSectionState();
}

class _AgentActionEditorSchedulingSectionState extends State<AgentActionEditorSchedulingSection> {
  List<AgentActionTrigger> _triggers = [];
  bool _loading = false;
  String? _error;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(AgentActionEditorSchedulingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionId != widget.actionId) unawaited(_reload());
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    final actionId = widget.actionId;
    if (actionId == null) {
      setState(() {
        _triggers = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.provider.loadTriggersForAction(actionId);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = false;
      result.fold((value) => _triggers = value, (failure) {
        _triggers = [];
        _error = AgentActionFailureDiagnosticsResolver.userMessage(failure);
      });
    });
  }

  Future<void> _edit([AgentActionTrigger? trigger]) async {
    final actionId = widget.actionId;
    if (actionId == null) return;
    await showAgentActionTriggerSaveDialog(
      context: context,
      provider: widget.provider,
      l10n: widget.l10n,
      actionId: actionId,
      existing: trigger,
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    if (widget.manualOnly) return Text(l10n.agentActionsEditorScheduleLocalOnly, style: context.bodyMuted);
    if (widget.actionId == null) return Text(l10n.agentActionsEditorScheduleSaveFirst, style: context.bodyMuted);
    final nextRuns =
        _triggers
            .where(
              (trigger) =>
                  trigger.isEnabled && trigger.nextRunAt != null && !trigger.nextRunAt!.isBefore(DateTime.now()),
            )
            .map((trigger) => trigger.nextRunAt!)
            .toList()
          ..sort();
    final canManage = widget.enabled && widget.provider.canManageTriggers && !widget.provider.isSavingTrigger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.agentActionsEditorScheduleHint, style: context.bodyMuted),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Button(
              key: const ValueKey('agent_action_editor_add_trigger'),
              onPressed: canManage && !_loading ? () => unawaited(_edit()) : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.add, size: 12),
                  const SizedBox(width: AppSpacing.xs),
                  Text(l10n.agentActionsTriggerAdd),
                ],
              ),
            ),
            Tooltip(
              message: l10n.agentActionsRefresh,
              child: IconButton(
                icon: Icon(FluentIcons.refresh, semanticLabel: l10n.agentActionsRefresh),
                onPressed: !_loading ? () => unawaited(_reload()) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loading)
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(dimension: 20, child: ProgressRing(strokeWidth: 2)),
          )
        else if (_error != null)
          InfoBar(
            title: Text(l10n.agentActionsErrorTitle),
            content: SelectableText(_error!),
            severity: InfoBarSeverity.error,
            isLong: true,
          )
        else ...[
          Text(
            nextRuns.isEmpty
                ? l10n.agentActionsEditorNoScheduledRun
                : l10n.agentActionsEditorNextRun(
                    DateFormat.yMd(l10n.localeName).add_Hm().format(nextRuns.first.toLocal()),
                  ),
            style: context.bodyStrong,
          ),
          if (_triggers.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.agentActionsTriggersEmpty, style: context.bodyMuted),
          ],
          for (final trigger in _triggers) ...[
            const SizedBox(height: AppSpacing.sm),
            _EditorTriggerCard(
              trigger: trigger,
              l10n: l10n,
              canEdit: canManage,
              onEdit: () => unawaited(_edit(trigger)),
            ),
          ],
        ],
      ],
    );
  }
}

class _EditorTriggerCard extends StatelessWidget {
  const _EditorTriggerCard({
    required this.trigger,
    required this.l10n,
    required this.canEdit,
    required this.onEdit,
  });

  final AgentActionTrigger trigger;
  final AppLocalizations l10n;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final nextRun = trigger.nextRunAt;
    final scheduleLabel = nextRun == null
        ? l10n.agentActionsTriggerNotScheduled
        : l10n.agentActionsTriggerNextRun(
            DateFormat.yMd(l10n.localeName).add_Hm().format(nextRun.toLocal()),
          );
    final notes = agentActionTriggerScheduleNotes(trigger, l10n);
    final statusLabel = trigger.isEnabled ? l10n.agentActionsTriggerEnabled : l10n.agentActionsTriggerDisabled;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(agentActionTriggerDisplayTitle(trigger, l10n), style: context.bodyStrong),
                        _TriggerStatusChip(label: statusLabel, enabled: trigger.isEnabled),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(agentActionTriggerTypeLabel(trigger.type, l10n), style: context.bodyMuted),
                    Text(scheduleLabel, style: context.bodyText),
                    if (notes != null) Text(notes, style: context.captionText),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Button(
                onPressed: canEdit ? onEdit : null,
                child: Text(l10n.agentActionsTriggerEdit),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AgentActionCopyableIdentifier(
            value: trigger.id,
            label: l10n.agentActionsTriggerIdLabel,
            placement: 'editor_trigger',
            l10n: l10n,
            copyTooltip: l10n.agentActionsCopyTriggerId,
            copiedMessage: l10n.agentActionsTriggerIdCopied,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _TriggerStatusChip extends StatelessWidget {
  const _TriggerStatusChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? context.appColors.success : context.appColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(label, style: context.captionStrong.copyWith(color: color)),
    );
  }
}
