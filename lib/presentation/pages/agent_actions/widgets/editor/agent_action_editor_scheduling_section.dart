import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.agentActionsEditorScheduleHint, style: context.bodyMuted),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Button(
              key: const ValueKey('agent_action_editor_add_trigger'),
              onPressed:
                  widget.enabled && widget.provider.canManageTriggers && !widget.provider.isSavingTrigger && !_loading
                  ? () => unawaited(_edit())
                  : null,
              child: Text(l10n.agentActionsTriggerAdd),
            ),
            Button(onPressed: !_loading ? () => unawaited(_reload()) : null, child: Text(l10n.agentActionsRefresh)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const ProgressRing()
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
            style: context.bodyMuted,
          ),
          if (_triggers.isEmpty) Text(l10n.agentActionsTriggersEmpty, style: context.bodyMuted),
          for (final trigger in _triggers)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(agentActionTriggerDisplayTitle(trigger, l10n), style: context.bodyStrong),
                        Text(agentActionTriggerSummaryLine(trigger, l10n), style: context.bodyMuted),
                      ],
                    ),
                  ),
                  Button(
                    onPressed: widget.enabled && widget.provider.canManageTriggers && !widget.provider.isSavingTrigger
                        ? () => unawaited(_edit(trigger))
                        : null,
                    child: Text(l10n.agentActionsTriggerEdit),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
