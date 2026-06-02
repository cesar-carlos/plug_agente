import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_operational_readiness_provider.dart';
import 'package:provider/provider.dart';

class AgentOperationalReadinessStrip extends StatelessWidget {
  const AgentOperationalReadinessStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = context.watch<AgentOperationalReadinessProvider>().snapshot;

    final hubLabel = switch (snapshot.hubPhase) {
      HubConnectionPhase.connected => l10n.agentOperationalReadinessHubConnected,
      HubConnectionPhase.connecting || HubConnectionPhase.reconnecting =>
        l10n.agentOperationalReadinessHubConnecting,
      HubConnectionPhase.error => l10n.agentOperationalReadinessHubError,
      HubConnectionPhase.disconnected => l10n.agentOperationalReadinessHubDisconnected,
    };

    final tokenLabel = l10n.agentOperationalReadinessActiveClientTokens(snapshot.activeClientTokenCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(
              icon: snapshot.hubConnected ? FluentIcons.check_mark : FluentIcons.circle_pause,
              label: hubLabel,
              color: snapshot.hubConnected ? context.appColors.success : context.appColors.disabled,
            ),
            _StatusChip(
              icon: FluentIcons.contact,
              label: tokenLabel,
              color: snapshot.activeClientTokenCount > 0
                  ? context.appColors.success
                  : context.appColors.warning,
            ),
            if (snapshot.hasSchedulerIssue)
              _StatusChip(
                icon: FluentIcons.warning,
                label: l10n.agentOperationalReadinessSchedulerIssue,
                color: context.appColors.warning,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: context.bodyText.copyWith(fontSize: 12, color: color),
        ),
      ],
    );
  }
}
