import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_paged_output.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionTestPreview extends StatelessWidget {
  const AgentActionTestPreview({
    required this.provider,
    required this.l10n,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final commandPreview = provider.lastTestCommandPreview;
    final previewError = provider.lastTestPreviewErrorMessage;
    final diagnostics = provider.lastTestDiagnostics;
    if ((commandPreview == null || commandPreview.isEmpty) &&
        (previewError == null || previewError.isEmpty) &&
        diagnostics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: AgentActionsPageKeys.testPreview,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agentActionsTestPreviewTitle, style: context.captionText),
          if (commandPreview != null && commandPreview.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            AgentActionOutputBlock(
              label: l10n.agentActionsTestPreviewCommandLabel,
              value: commandPreview,
              truncated: false,
              l10n: l10n,
            ),
          ],
          if (previewError != null && previewError.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            InfoBar(
              title: Text(l10n.agentActionsTestPreviewUnavailableTitle),
              content: Text(previewError),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
          if (diagnostics.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: diagnostics.entries
                  .where((entry) => entry.key != 'path_snapshot_warnings')
                  .map(
                    (entry) => AgentActionDiagnosticLine(
                      label: agentActionTestDiagnosticLabel(entry.key, l10n),
                      value: agentActionTestDiagnosticValue(entry.key, entry.value, l10n),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (diagnostics['path_snapshot_warnings'] is List) ...[
            const SizedBox(height: AppSpacing.xs),
            AgentActionOutputBlock(
              label: l10n.agentActionsTestPreviewPathSnapshotWarnings,
              value: (diagnostics['path_snapshot_warnings']! as List)
                  .map(
                    (warning) =>
                        warning is Map ? warning['message']?.toString() ?? warning.toString() : warning.toString(),
                  )
                  .join('\n'),
              truncated: false,
              l10n: l10n,
            ),
          ],
        ],
      ),
    );
  }
}
