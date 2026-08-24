import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/application/actions/agent_action_remote_audit_support_export.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_remote_audit_labels.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_empty_state.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_select_builder.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsRemoteAuditPanel extends StatefulWidget {
  const AgentActionsRemoteAuditPanel({
    required this.provider,
    required this.l10n,
    this.onShowInHistory,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  /// Called after a remote audit entry is successfully correlated to a history
  /// execution. Use this to switch the parent's tab to History.
  final VoidCallback? onShowInHistory;

  @override
  State<AgentActionsRemoteAuditPanel> createState() => _AgentActionsRemoteAuditPanelState();
}

class _AgentActionsRemoteAuditPanelState extends State<AgentActionsRemoteAuditPanel> {
  static const AgentActionRemoteAuditSupportExport _recordExport = AgentActionRemoteAuditSupportExport();
  static final DateFormat _occurredFormat = DateFormat('yyyy-MM-dd HH:mm');

  AgentActionRemoteAuditViewFilter _filter = AgentActionRemoteAuditViewFilter.all;

  AppLocalizations get l10n => widget.l10n;

  AgentActionsProvider get provider => widget.provider;

  List<AgentActionRemoteAuditRecord> get _visibleEntries => provider.remoteAuditEntries
      .where((record) => matchesAgentActionRemoteAuditViewFilter(_filter, record.outcome))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return AgentActionsSelectBuilder(
      listenable: provider,
      selector: () => Object.hashAll([
        provider.isLoadingRemoteAudit,
        provider.remoteAuditLoadError,
        identityHashCode(provider.remoteAuditEntries),
        provider.remoteAuditEntries.length,
      ]),
      builder: _buildPanel,
    );
  }

  Widget _buildPanel(BuildContext context) {
    final visibleEntries = _visibleEntries;
    final hasAnyRows = provider.remoteAuditEntries.isNotEmpty;

    return SizedBox.expand(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Expanded(
              child: !hasAnyRows && provider.remoteAuditLoadError == null
                  ? AgentActionsEmptyState(
                      icon: FluentIcons.cloud,
                      message: l10n.agentActionsRemoteAuditEmpty,
                    )
                  : visibleEntries.isEmpty
                  ? AgentActionsEmptyState(
                      icon: FluentIcons.filter,
                      message: l10n.agentActionsRemoteAuditFilterEmpty,
                    )
                  : ListView.separated(
                      itemCount: visibleEntries.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        return _RemoteAuditEntryTile(
                          record: visibleEntries[index],
                          occurredFormat: _occurredFormat,
                          l10n: l10n,
                          onCopy: () => unawaited(_copyRecordJson(context, visibleEntries[index])),
                          onShowInHistory: () => _onShowInHistory(context, visibleEntries[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _filterButtons() {
    return AgentActionRemoteAuditViewFilter.values
        .map((value) {
          final label = switch (value) {
            AgentActionRemoteAuditViewFilter.all => l10n.agentActionsRemoteAuditFilterAll,
            AgentActionRemoteAuditViewFilter.rpc => l10n.agentActionsRemoteAuditFilterRpc,
            AgentActionRemoteAuditViewFilter.lifecycle => l10n.agentActionsRemoteAuditFilterLifecycle,
          };
          final isSelected = _filter == value;
          return ToggleButton(
            checked: isSelected,
            onChanged: (_) {
              setState(() {
                _filter = value;
              });
            },
            child: Text(label),
          );
        })
        .toList(growable: false);
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
      widget.onShowInHistory?.call();
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
      builder: (closeContext, void Function() close) => InfoBar(
        key: const ValueKey<String>('agent_actions_remote_audit_focus_warning'),
        title: title,
        severity: InfoBarSeverity.warning,
        isLong: true,
        onClose: close,
      ),
    );
  }

  Future<void> _copyJson(BuildContext context) async {
    await _copyText(context, provider.buildRemoteAuditJsonExport());
  }

  Future<void> _copyRecordJson(BuildContext context, AgentActionRemoteAuditRecord record) async {
    await _copyText(context, _recordExport.buildJson([record]));
  }

  Future<void> _copyText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (closeContext, void Function() close) => InfoBar(
        title: Text(l10n.agentActionsRemoteAuditCopiedToast),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }
}

class _RemoteAuditEntryTile extends StatelessWidget {
  const _RemoteAuditEntryTile({
    required this.record,
    required this.occurredFormat,
    required this.l10n,
    required this.onCopy,
    required this.onShowInHistory,
  });

  final AgentActionRemoteAuditRecord record;
  final DateFormat occurredFormat;
  final AppLocalizations l10n;
  final VoidCallback onCopy;
  final VoidCallback onShowInHistory;

  @override
  Widget build(BuildContext context) {
    final when = occurredFormat.format(record.occurredAtUtc.toLocal());
    final outcomeLabel = agentActionRemoteAuditOutcomeLabel(l10n, record.outcome);
    final subtitle = formatAgentActionRemoteAuditSubtitle(l10n, record);
    final title = '${record.rpcMethod} · $outcomeLabel · $when';
    final actionId = record.actionId?.trim();
    final canCorrelate = actionId != null && actionId.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: title,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            SelectableText(subtitle, style: context.captionText),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: l10n.agentActionsRemoteAuditCopyJson,
                child: Semantics(
                  button: true,
                  label: l10n.agentActionsRemoteAuditCopyJson,
                  child: IconButton(
                    key: ValueKey<String>('agent_actions_remote_audit_copy_${record.id}'),
                    icon: const Icon(FluentIcons.copy, size: 14),
                    onPressed: onCopy,
                  ),
                ),
              ),
              if (canCorrelate)
                HyperlinkButton(
                  onPressed: onShowInHistory,
                  child: Text(l10n.agentActionsRemoteAuditShowInHistory),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
