import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsSummaryCard extends StatelessWidget {
  const AgentActionsSummaryCard({
    required this.provider,
    required this.l10n,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          _Metric(label: l10n.agentActionsSummaryActions, value: provider.definitions.length.toString()),
          _Metric(label: l10n.agentActionsSummaryQueued, value: provider.summaryQueuedCount.toString()),
          _Metric(label: l10n.agentActionsSummaryRunning, value: provider.summaryRunningCount.toString()),
          _Metric(label: l10n.agentActionsSummaryFailed, value: provider.failedCount.toString()),
          if (provider.isMaintenanceMode)
            _Metric(
              label: l10n.agentActionsSummaryMaintenance,
              value: l10n.agentActionsSummaryMaintenanceActive,
            ),
          if (provider.comObjectHandlersRegisteredCount case final int count)
            _Metric(
              label: l10n.agentActionsSummaryComHandlers,
              value: count > 0
                  ? count.toString()
                  : l10n.agentActionsSummaryComHandlersNone,
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.bodyMuted),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: context.sectionTitle),
        ],
      ),
    );
  }
}
