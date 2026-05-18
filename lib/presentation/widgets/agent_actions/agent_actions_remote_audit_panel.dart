import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsRemoteAuditPanel extends StatelessWidget {
  const AgentActionsRemoteAuditPanel({
    required this.provider,
    required this.l10n,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  static final DateFormat _occurredFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
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
          if (provider.remoteAuditEntries.isEmpty && provider.remoteAuditLoadError == null)
            Text(l10n.agentActionsRemoteAuditEmpty, style: context.bodyMuted)
          else
            SizedBox(
              height: 200,
              child: ListView.separated(
                itemCount: provider.remoteAuditEntries.length,
                separatorBuilder: (BuildContext context, int index) => const Divider(),
                itemBuilder: (BuildContext context, int index) {
                  final record = provider.remoteAuditEntries[index];
                  final when = _occurredFormat.format(record.occurredAtUtc.toLocal());
                  final subtitle = _subtitle(record);
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
                              Text('${record.rpcMethod} · ${record.outcome} · $when'),
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

  void _onShowInHistory(BuildContext context, AgentActionRemoteAuditRecord record) {
    unawaited(_showInHistoryAsync(context, record));
  }

  Future<void> _showInHistoryAsync(BuildContext context, AgentActionRemoteAuditRecord record) async {
    final ok = await provider.focusExecutionFromRemoteAudit(record);
    if (!context.mounted) {
      return;
    }
    final executionId = record.executionId?.trim();
    if (!ok && executionId != null && executionId.isNotEmpty) {
      displayInfoBar(
        context,
        builder: (BuildContext closeContext, void Function() close) => InfoBar(
          title: Text(l10n.agentActionsRemoteAuditExecutionNotInHistory(executionId)),
          severity: InfoBarSeverity.warning,
          isLong: true,
          onClose: close,
        ),
      );
    }
  }

  String _subtitle(AgentActionRemoteAuditRecord record) {
    final parts = <String>[
      if (record.actionId != null && record.actionId!.trim().isNotEmpty) 'action: ${record.actionId}',
      if (record.executionId != null && record.executionId!.trim().isNotEmpty) 'exec: ${record.executionId}',
      if (record.traceId != null && record.traceId!.trim().isNotEmpty) 'trace: ${record.traceId}',
      if (record.clientId != null && record.clientId!.trim().isNotEmpty) 'client: ${record.clientId}',
      if (record.runtimeInstanceId != null && record.runtimeInstanceId!.trim().isNotEmpty)
        'inst: ${record.runtimeInstanceId}',
      if (record.runtimeSessionId != null && record.runtimeSessionId!.trim().isNotEmpty)
        'sess: ${record.runtimeSessionId}',
    ];
    return parts.join(' · ');
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
