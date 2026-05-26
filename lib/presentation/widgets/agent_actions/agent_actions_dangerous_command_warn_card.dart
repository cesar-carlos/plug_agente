import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

/// Read-only homologation notice for dangerous-command warn mode (feature flag).
class AgentActionsDangerousCommandWarnCard extends StatelessWidget {
  const AgentActionsDangerousCommandWarnCard({
    required this.provider,
    required this.l10n,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (!provider.isFeatureEnabled) {
      return const SizedBox.shrink();
    }

    final enabled = provider.isDangerousCommandWarnModeEnabled;
    return AppCard(
      child: InfoBar(
        title: Text(l10n.agentActionsDangerousCommandWarnModeTitle),
        severity: enabled ? InfoBarSeverity.warning : InfoBarSeverity.info,
        content: Text(
          enabled
              ? l10n.agentActionsDangerousCommandWarnModeEnabled
              : l10n.agentActionsDangerousCommandWarnModeDisabled,
        ),
        isLong: true,
      ),
    );
  }
}
