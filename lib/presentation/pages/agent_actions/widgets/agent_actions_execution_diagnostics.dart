import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_keys.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_paged_output.dart';
import 'package:result_dart/result_dart.dart';

String? formatAgentActionExecutionDuration(AgentActionExecution execution) {
  final startedAt = execution.processStartedAt;
  final finishedAt = execution.finishedAt;
  if (startedAt == null || finishedAt == null) {
    return null;
  }

  final duration = finishedAt.difference(startedAt);
  if (duration.isNegative) {
    return null;
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }

  return '$minutes:$seconds';
}

class AgentActionExecutionDiagnostics extends StatefulWidget {
  const AgentActionExecutionDiagnostics({
    required this.execution,
    required this.l10n,
    required this.onSliceCapturedOutput,
    super.key,
  });

  static const AgentActionFailureDiagnosticsResolver _diagnosticsResolver = AgentActionFailureDiagnosticsResolver();

  final AgentActionExecution execution;
  final AppLocalizations l10n;
  final Future<Result<CapturedOutputUtf8Window>> Function({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    int? maxBytes,
  })
  onSliceCapturedOutput;

  @override
  State<AgentActionExecutionDiagnostics> createState() => AgentActionExecutionDiagnosticsState();
}

class AgentActionExecutionDiagnosticsState extends State<AgentActionExecutionDiagnostics> {
  static const AgentActionExecutionSupportExport _supportExport = AgentActionExecutionSupportExport();

  Future<void> _copySupportExport(BuildContext context) async {
    final text = _supportExport.buildJson(widget.execution);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(widget.l10n.agentActionsDiagnosticsCopiedToast),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final execution = widget.execution;
    final l10n = widget.l10n;
    final stdoutText = execution.stdoutText;
    final stderrText = execution.stderrText;
    final showStdout = execution.stdoutStoredInChunks || (stdoutText != null && stdoutText.isNotEmpty);
    final showStderr = execution.stderrStoredInChunks || (stderrText != null && stderrText.isNotEmpty);
    final duration = formatAgentActionExecutionDuration(execution);
    final diagnostics = AgentActionExecutionDiagnostics._diagnosticsResolver.resolve(execution);
    final correctiveAction = agentActionCorrectiveActionLabel(
      diagnostics.correctiveAction,
      l10n,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.agentActionsDiagnosticsTitle, style: context.captionText),
              ),
              Button(
                key: AgentActionsPageKeys.executionSupportCopyButton(execution.id),
                onPressed: () {
                  unawaited(_copySupportExport(context));
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.copy, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l10n.agentActionsDiagnosticsCopySupport),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              AgentActionDiagnosticLine(
                label: l10n.agentActionsDiagnosticsExecutionId,
                value: execution.id,
              ),
              AgentActionDiagnosticLine(
                label: l10n.agentActionsDiagnosticsSource,
                value: agentActionRequestSourceLabel(execution.source, l10n),
              ),
              if (execution.queueStartedAt != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsQueueStartedAt,
                  value: execution.queueStartedAt!.toLocal().toString(),
                ),
              if (execution.idempotencyKey != null && execution.idempotencyKey!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsIdempotencyKey,
                  value: execution.idempotencyKey!.trim(),
                ),
              if (execution.requestedBy != null && execution.requestedBy!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRequestedBy,
                  value: execution.requestedBy!.trim(),
                ),
              if (execution.traceId != null && execution.traceId!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTraceId,
                  value: execution.traceId!.trim(),
                ),
              if (execution.runtimeInstanceId != null && execution.runtimeInstanceId!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRuntimeInstanceId,
                  value: execution.runtimeInstanceId!.trim(),
                ),
              if (execution.runtimeSessionId != null && execution.runtimeSessionId!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRuntimeSessionId,
                  value: execution.runtimeSessionId!.trim(),
                ),
              if (execution.triggerId != null && execution.triggerId!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTriggerId,
                  value: execution.triggerId!.trim(),
                ),
              if (execution.triggerType != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTriggerType,
                  value: agentActionTriggerTypeLabel(execution.triggerType!, l10n),
                ),
              if (execution.scheduledAt != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsScheduledAt,
                  value: execution.scheduledAt!.toLocal().toString(),
                ),
              if (execution.triggeredAt != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTriggeredAt,
                  value: execution.triggeredAt!.toLocal().toString(),
                ),
              if (execution.pid != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsPid,
                  value: execution.pid.toString(),
                ),
              if (execution.processStartedAt != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsStartedAt,
                  value: execution.processStartedAt!.toLocal().toString(),
                ),
              if (execution.finishedAt != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsFinishedAt,
                  value: execution.finishedAt!.toLocal().toString(),
                ),
              if (execution.timeoutAt != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsTimeoutAt,
                  value: execution.timeoutAt!.toLocal().toString(),
                ),
              if (duration != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsDuration,
                  value: duration,
                ),
              if (execution.processExecutable != null && execution.processExecutable!.isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsExecutable,
                  value: execution.processExecutable!,
                ),
              if (execution.processArgumentCount != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsArgumentCount,
                  value: execution.processArgumentCount.toString(),
                ),
              if (execution.processCommandPreview != null && execution.processCommandPreview!.isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsCommandPreview,
                  value: execution.processCommandPreview!,
                ),
              if (execution.definitionSnapshotHash != null && execution.definitionSnapshotHash!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsDefinitionSnapshotHash,
                  value: execution.definitionSnapshotHash!.trim(),
                ),
              if (execution.contextHash != null && execution.contextHash!.trim().isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsContextHash,
                  value: execution.contextHash!.trim(),
                ),
              if (execution.redactionApplied)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsRedactionApplied,
                  value: l10n.agentActionsDiagnosticsValueYes,
                ),
              if (execution.failureCode != null && execution.failureCode!.isNotEmpty)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsFailureCode,
                  value: execution.failureCode!,
                ),
              if (diagnostics.failurePhase != null)
                AgentActionDiagnosticLine(
                  label: l10n.agentActionsDiagnosticsFailurePhase,
                  value: localizeAgentActionFailurePhase(diagnostics.failurePhase!, l10n),
                ),
            ],
          ),
          if (correctiveAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AgentActionOutputBlock(
              label: l10n.agentActionsDiagnosticsCorrectiveAction,
              value: correctiveAction,
              truncated: false,
              l10n: l10n,
            ),
          ],
          if (showStdout) ...[
            const SizedBox(height: AppSpacing.xs),
            AgentActionPagedCapturedOutput(
              label: l10n.agentActionsDiagnosticsStdout,
              loadMoreLabel: l10n.agentActionsDiagnosticsLoadMoreStdout,
              fullText: stdoutText,
              storedInChunks: execution.stdoutStoredInChunks,
              storageTruncated: execution.stdoutTruncated,
              l10n: l10n,
              onSlice: execution.stdoutStoredInChunks
                  ? (int offsetUtf8, int maxBytes) => widget.onSliceCapturedOutput(
                      executionId: execution.id,
                      stream: AgentActionCapturedOutputConstants.stdoutStream,
                      offsetUtf8: offsetUtf8,
                      maxBytes: maxBytes,
                    )
                  : null,
            ),
          ],
          if (showStderr) ...[
            const SizedBox(height: AppSpacing.xs),
            AgentActionPagedCapturedOutput(
              label: l10n.agentActionsDiagnosticsStderr,
              loadMoreLabel: l10n.agentActionsDiagnosticsLoadMoreStderr,
              fullText: stderrText,
              storedInChunks: execution.stderrStoredInChunks,
              storageTruncated: execution.stderrTruncated,
              l10n: l10n,
              onSlice: execution.stderrStoredInChunks
                  ? (int offsetUtf8, int maxBytes) => widget.onSliceCapturedOutput(
                      executionId: execution.id,
                      stream: AgentActionCapturedOutputConstants.stderrStream,
                      offsetUtf8: offsetUtf8,
                      maxBytes: maxBytes,
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
