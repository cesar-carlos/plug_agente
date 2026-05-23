import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_status_strip.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_dangerous_command_warn_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_preflight_settings_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_retention_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_runtime_support_card.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_summary_card.dart';

class AgentActionsSettingsTab extends StatelessWidget {
  const AgentActionsSettingsTab({
    required this.provider,
    required this.l10n,
    required this.runtimeCapabilities,
    required this.runtimeDiagnostics,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final RuntimeCapabilities runtimeCapabilities;
  final RuntimeDetectionDiagnostics? runtimeDiagnostics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AgentActionsSummaryCard(provider: provider, l10n: l10n),
        const SizedBox(height: AppSpacing.md),
        ...buildAgentActionElevatedRunnerStatusWidgets(provider, l10n),
        AgentActionsPreflightSettingsCard(provider: provider, l10n: l10n),
        const SizedBox(height: AppSpacing.md),
        AgentActionsDangerousCommandWarnCard(provider: provider, l10n: l10n),
        const SizedBox(height: AppSpacing.md),
        AgentActionsRetentionCard(l10n: l10n, provider: provider),
        if (runtimeCapabilities.isDegraded ||
            runtimeCapabilities.isUnsupported ||
            runtimeDiagnostics?.source == RuntimeDetectionSource.detectionFailed) ...[
          const SizedBox(height: AppSpacing.md),
          AgentActionsRuntimeSupportCard(
            capabilities: runtimeCapabilities,
            diagnostics: runtimeDiagnostics,
          ),
        ],
      ],
    );
  }
}
