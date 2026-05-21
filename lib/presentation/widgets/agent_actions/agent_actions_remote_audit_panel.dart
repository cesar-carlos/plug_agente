import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_remote_audit_labels.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsRemoteAuditPanel extends StatefulWidget {
  const AgentActionsRemoteAuditPanel({
    required this.provider,
    required this.l10n,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  State<AgentActionsRemoteAuditPanel> createState() => _AgentActionsRemoteAuditPanelState();
}

class _AgentActionsRemoteAuditPanelState extends State<AgentActionsRemoteAuditPanel> {
  static final DateFormat _occurredFormat = DateFormat('yyyy-MM-dd HH:mm');

  AgentActionRemoteAuditViewFilter _filter = AgentActionRemoteAuditViewFilter.all;

  AppLocalizations get l10n => widget.l10n;

  AgentActionsProvider get provider => widget.provider;

  List<AgentActionRemoteAuditRecord> get _visibleEntries => provider.remoteAuditEntries
      .where((AgentActionRemoteAuditRecord record) => matchesAgentActionRemoteAuditViewFilter(_filter, record.outcome))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _visibleEntries;
    final hasAnyRows = provider.remoteAuditEntries.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agentActionsRemoteAuditTitle, style: context.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.agentActionsRemoteAuditDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: provider.isLoadingRemoteAudit
                    ? null
                    : () {
                        unawaited(provider.refreshRemoteAudit());
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.isLoadingRemoteAudit) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(l10n.agentActionsRemoteAuditRefresh),
                  ],
                ),
              ),
              Button(
                onPressed: provider.remoteAuditEntries.isEmpty ? null : () => unawaited(_copyJson(context)),
                child: Text(l10n.agentActionsRemoteAuditCopyJson),
              ),
              ..._filterButtons(),
            ],
          ),
          if (provider.remoteAuditLoadError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsErrorTitle),
              content: SelectableText(provider.remoteAuditLoadError!),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (!hasAnyRows && provider.remoteAuditLoadError == null)
            Text(l10n.agentActionsRemoteAuditEmpty, style: context.bodyMuted)
          else if (visibleEntries.isEmpty)
            Text(l10n.agentActionsRemoteAuditFilterEmpty, style: context.bodyMuted)
          else
            SizedBox(
              height: 220,
              child: ListView.separated(
                itemCount: visibleEntries.length,
                separatorBuilder: (BuildContext context, int index) => const Divider(),
                itemBuilder: (BuildContext context, int index) {
                  final record = visibleEntries[index];
                  final when = _occurredFormat.format(record.occurredAtUtc.toLocal());
                  final outcomeLabel = agentActionRemoteAuditOutcomeLabel(l10n, record.outcome);
                  final subtitle = formatAgentActionRemoteAuditSubtitle(l10n, record);
                  final actionId = record.actionId?.trim();
                  final canCorrelate = actionId != null && actionId.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${record.rpcMethod} · $outcomeLabel · $when'),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                SelectableText(subtitle, style: context.captionText),
                              ],
                            ],
                          ),
                        ),
                        if (canCorrelate)
                          HyperlinkButton(
                            child: Text(l10n.agentActionsRemoteAuditShowInHistory),
                            onPressed: () => _onShowInHistory(context, record),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _filterButtons() {
    return AgentActionRemoteAuditViewFilter.values.map((AgentActionRemoteAuditViewFilter value) {
      final label = switch (value) {
        AgentActionRemoteAuditViewFilter.all => l10n.agentActionsRemoteAuditFilterAll,
        AgentActionRemoteAuditViewFilter.rpc => l10n.agentActionsRemoteAuditFilterRpc,
        AgentActionRemoteAuditViewFilter.lifecycle => l10n.agentActionsRemoteAuditFilterLifecycle,
      };
      final isSelected = _filter == value;
      return Button(
        onPressed: isSelected
            ? null
            : () {
                setState(() {
                  _filter = value;
                });
              },
        child: Text(label),
      );
    }).toList(growable: false);
  }

  void _onShowInHistory(BuildContext context, AgentActionRemoteAuditRecord record) {
    unawaited(_showInHistoryAsync(context, record));
  }

  Future<void> _showInHistoryAsync(BuildContext context, AgentActionRemoteAuditRecord record) async {
    final result = await provider.focusExecutionFromRemoteAudit(record);
    if (!context.mounted) {
      return;
    }
    if (result == AgentActionRemoteAuditFocusResult.succeeded) {
      return;
    }

    final executionId = record.executionId?.trim();
    if (executionId == null || executionId.isEmpty) {
      return;
    }

    final title = switch (result) {
      AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch => Text(
        l10n.agentActionsRemoteAuditRuntimeInstanceMismatch(
          executionId,
          record.runtimeInstanceId ?? '',
        ),
      ),
      _ => Text(l10n.agentActionsRemoteAuditExecutionNotInHistory(executionId)),
    };

    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        key: const ValueKey<String>('agent_actions_remote_audit_focus_warning'),
        title: title,
        severity: InfoBarSeverity.warning,
        isLong: true,
        onClose: close,
      ),
    );
  }

  Future<void> _copyJson(BuildContext context) async {
    final text = provider.buildRemoteAuditJsonExport();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(l10n.agentActionsRemoteAuditCopiedToast),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }
}
