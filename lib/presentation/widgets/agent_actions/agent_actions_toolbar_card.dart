import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsToolbarCard extends StatelessWidget {
  const AgentActionsToolbarCard({
    required this.provider,
    required this.l10n,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 960) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _buildActionControls(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                ToggleSwitch(
                  checked: provider.isMaintenanceMode,
                  onChanged: provider.isFeatureEnabled
                      ? (value) {
                          unawaited(provider.setMaintenanceMode(enabled: value));
                        }
                      : null,
                  content: Text(l10n.agentActionsMaintenanceMode),
                ),
              ],
            );
          }

          return Row(
            children: [
              ..._buildActionControls(context),
              const Spacer(),
              ToggleSwitch(
                checked: provider.isMaintenanceMode,
                onChanged: provider.isFeatureEnabled
                    ? (value) {
                        unawaited(provider.setMaintenanceMode(enabled: value));
                      }
                    : null,
                content: Text(l10n.agentActionsMaintenanceMode),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildActionControls(BuildContext context) {
    return [
      Button(
        onPressed: provider.isLoading ? null : provider.load,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.refresh),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsRefresh),
          ],
        ),
      ),
      FilledButton(
        onPressed: provider.canRunSelected ? provider.runSelectedAction : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isRunning)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.play),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsRunSelected),
          ],
        ),
      ),
      Button(
        onPressed: provider.canTestSelected ? provider.testSelectedAction : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider.isTesting)
              const SizedBox.square(
                dimension: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.test_beaker),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.agentActionsTestSelected),
          ],
        ),
      ),
      if (provider.hasLiveQueueActivity)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.processing, size: 14, color: FluentTheme.of(context).accentColor),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l10n.agentActionsQueueActiveIndicator(
                provider.liveQueuePendingCount,
                provider.liveQueueRunningCount,
              ),
              style: context.captionText,
            ),
          ],
        ),
    ];
  }
}
