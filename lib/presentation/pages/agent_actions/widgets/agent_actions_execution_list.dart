import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_execution_diagnostics.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionExecutionList extends StatelessWidget {
  const AgentActionExecutionList({
    required this.executions,
    required this.provider,
    required this.l10n,
  });

  final List<AgentActionExecution> executions;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (executions.isEmpty) {
      return Center(
        child: Text(
          l10n.agentActionsEmptyHistory,
          style: context.bodyMuted,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: executions.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final execution = executions[index];
        return AgentActionExecutionRow(
          execution: execution,
          provider: provider,
          l10n: l10n,
        );
      },
    );
  }
}

class AgentActionExecutionRow extends StatelessWidget {
  const AgentActionExecutionRow({
    required this.execution,
    required this.provider,
    required this.l10n,
  });

  final AgentActionExecution execution;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final failureMessage = execution.failureMessage;
    final isAuditHighlight =
        provider.auditCorrelationExecutionId != null && provider.auditCorrelationExecutionId == execution.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Container(
        decoration: isAuditHighlight
            ? BoxDecoration(
                border: Border.all(
                  color: FluentTheme.of(context).accentColor,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        padding: isAuditHighlight ? const EdgeInsets.all(AppSpacing.xs) : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(agentActionExecutionStatusIcon(execution.status), size: 16),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agentActionExecutionStatusLabel(execution.status, l10n)),
                      const SizedBox(height: 2),
                      Text(
                        agentActionExecutionSubtitle(execution, l10n),
                        style: context.captionText,
                      ),
                      if (execution.failurePhase != null &&
                          execution.failurePhase!.trim().isNotEmpty &&
                          !execution.status.isSuccess) ...[
                        const SizedBox(height: 2),
                        Text(
                          l10n.agentActionsExecutionFailurePhaseLabel(
                            localizeAgentActionFailurePhase(execution.failurePhase!, l10n),
                          ),
                          style: context.captionText,
                        ),
                      ],
                      if (failureMessage != null && failureMessage.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        SelectableText(failureMessage, style: context.captionText),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Tooltip(
                  message: l10n.agentActionsCancelExecution,
                  child: Semantics(
                    button: true,
                    label: l10n.agentActionsCancelExecution,
                    child: IconButton(
                      icon: provider.hasCancellationInProgress(execution.id)
                          ? const SizedBox.square(
                              dimension: 14,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          : const Icon(FluentIcons.cancel),
                      onPressed: provider.canCancelExecution(execution)
                          ? () {
                              unawaited(provider.cancelExecution(execution));
                            }
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AgentActionExecutionDiagnostics(
              key: ValueKey<String>('execution-diagnostics-${execution.id}'),
              execution: execution,
              l10n: l10n,
              onSliceCapturedOutput: provider.sliceCapturedOutput,
            ),
          ],
        ),
      ),
    );
  }
}
