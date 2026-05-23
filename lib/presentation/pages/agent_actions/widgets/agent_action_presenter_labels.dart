import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

IconData agentActionTypeIcon(AgentActionType type) {
  return switch (type) {
    AgentActionType.commandLine => FluentIcons.command_prompt,
    AgentActionType.executable => FluentIcons.processing,
    AgentActionType.script => FluentIcons.script,
    AgentActionType.jar => FluentIcons.file_code,
    AgentActionType.email => FluentIcons.mail,
    AgentActionType.comObject => FluentIcons.code,
    AgentActionType.developer => FluentIcons.developer_tools,
  };
}

IconData agentActionDefinitionIconFor(AgentActionDefinition definition) {
  return isAgentActionPowerShellDefinition(definition) ? FluentIcons.command_prompt : agentActionTypeIcon(definition.type);
}

IconData agentActionExecutionStatusIcon(AgentActionExecutionStatus status) {
  return switch (status) {
    AgentActionExecutionStatus.queued => FluentIcons.clock,
    AgentActionExecutionStatus.running => FluentIcons.processing,
    AgentActionExecutionStatus.succeeded => FluentIcons.completed,
    AgentActionExecutionStatus.failed => FluentIcons.error,
    AgentActionExecutionStatus.skipped => FluentIcons.red_eye,
    AgentActionExecutionStatus.cancelled => FluentIcons.cancel,
    AgentActionExecutionStatus.killed => FluentIcons.blocked,
    AgentActionExecutionStatus.timedOut => FluentIcons.timer,
    AgentActionExecutionStatus.interrupted => FluentIcons.warning,
    AgentActionExecutionStatus.unknown => FluentIcons.help,
  };
}

String agentActionDefinitionSubtitle(AgentActionDefinition definition, AppLocalizations l10n) {
  return '${agentActionDefinitionTypeLabel(definition, l10n)} - ${agentActionStateLabel(definition.state, l10n)}';
}

String agentActionExecutionSubtitle(AgentActionExecution execution, AppLocalizations l10n) {
  final exitCode = execution.exitCode == null ? '' : ' - ${l10n.agentActionsExitCode}: ${execution.exitCode}';
  final chunks = execution.stdoutStoredInChunks || execution.stderrStoredInChunks
      ? ' - ${l10n.agentActionsExecutionOutputInChunks}'
      : '';
  return '${l10n.agentActionsRequestedAt}: ${execution.requestedAt.toLocal()}$exitCode$chunks';
}

String agentActionTypeLabel(AgentActionType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionType.commandLine => l10n.agentActionsTypeCommandLine,
    AgentActionType.executable => l10n.agentActionsTypeExecutable,
    AgentActionType.script => l10n.agentActionsTypeScript,
    AgentActionType.jar => l10n.agentActionsTypeJar,
    AgentActionType.email => l10n.agentActionsTypeEmail,
    AgentActionType.comObject => l10n.agentActionsTypeComObject,
    AgentActionType.developer => l10n.agentActionsTypeDeveloper,
  };
}

String agentActionDefinitionTypeLabel(AgentActionDefinition definition, AppLocalizations l10n) {
  return isAgentActionPowerShellDefinition(definition) ? l10n.agentActionsTypePowerShell : agentActionTypeLabel(definition.type, l10n);
}

bool isAgentActionPowerShellDefinition(AgentActionDefinition definition) {
  return switch (definition.config) {
    CommandLineActionConfig(:final command) => PowerShellCommandLine.tryUnwrapInlineCommand(command) != null,
    ScriptActionConfig(:final scriptPath) => PowerShellCommandLine.isPowerShellScriptPath(scriptPath.originalPath),
    _ => false,
  };
}

String agentActionStateLabel(AgentActionState state, AppLocalizations l10n) {
  return switch (state) {
    AgentActionState.active => l10n.agentActionsStateActive,
    AgentActionState.paused => l10n.agentActionsStatePaused,
    AgentActionState.disabled => l10n.agentActionsStateDisabled,
    AgentActionState.needsValidation => l10n.agentActionsStateNeedsValidation,
  };
}

String agentActionExecutionStatusLabel(AgentActionExecutionStatus status, AppLocalizations l10n) {
  return switch (status) {
    AgentActionExecutionStatus.queued => l10n.agentActionsStatusQueued,
    AgentActionExecutionStatus.running => l10n.agentActionsStatusRunning,
    AgentActionExecutionStatus.succeeded => l10n.agentActionsStatusSucceeded,
    AgentActionExecutionStatus.failed => l10n.agentActionsStatusFailed,
    AgentActionExecutionStatus.skipped => l10n.agentActionsStatusSkipped,
    AgentActionExecutionStatus.cancelled => l10n.agentActionsStatusCancelled,
    AgentActionExecutionStatus.killed => l10n.agentActionsStatusKilled,
    AgentActionExecutionStatus.timedOut => l10n.agentActionsStatusTimedOut,
    AgentActionExecutionStatus.interrupted => l10n.agentActionsStatusInterrupted,
    AgentActionExecutionStatus.unknown => l10n.agentActionsStatusUnknown,
  };
}

String agentActionRequestSourceLabel(AgentActionRequestSource source, AppLocalizations l10n) {
  return switch (source) {
    AgentActionRequestSource.localUi => l10n.agentActionsSourceLocalUi,
    AgentActionRequestSource.scheduler => l10n.agentActionsSourceScheduler,
    AgentActionRequestSource.remoteHub => l10n.agentActionsSourceRemoteHub,
    AgentActionRequestSource.appLifecycle => l10n.agentActionsSourceAppLifecycle,
  };
}

String agentActionHistoryPeriodLabel(AgentActionHistoryPeriod period, AppLocalizations l10n) {
  return switch (period) {
    AgentActionHistoryPeriod.all => l10n.agentActionsHistoryPeriodAll,
    AgentActionHistoryPeriod.last24Hours => l10n.agentActionsHistoryPeriodLast24Hours,
    AgentActionHistoryPeriod.last3Days => l10n.agentActionsHistoryPeriodLast3Days,
  };
}

String agentActionTriggerDisplayTitle(AgentActionTrigger trigger, AppLocalizations l10n) {
  final name = trigger.name?.trim() ?? '';
  if (name.isEmpty) {
    return l10n.agentActionsTriggerUnnamed;
  }

  return name;
}

String agentActionTriggerDeleteConfirmLabel(AgentActionTrigger trigger, AppLocalizations l10n) {
  final name = trigger.name?.trim() ?? '';
  if (name.isEmpty) {
    return '${l10n.agentActionsTriggerUnnamed} (${trigger.id})';
  }

  return name;
}

String agentActionTriggerSummaryLine(AgentActionTrigger trigger, AppLocalizations l10n) {
  final typeLabel = agentActionTriggerTypeLabel(trigger.type, l10n);
  final statusLabel = trigger.isEnabled ? l10n.agentActionsTriggerEnabled : l10n.agentActionsTriggerDisabled;
  final next = trigger.nextRunAt;
  final scheduleLabel = next == null
      ? l10n.agentActionsTriggerNotScheduled
      : l10n.agentActionsTriggerNextRun(formatAgentActionTriggerLocalDateTime(next));

  final base = '$typeLabel · $statusLabel · $scheduleLabel';
  final ianaId = trigger.schedule.timezoneId?.trim();
  final withTimezone = (ianaId == null || ianaId.isEmpty)
      ? base
      : '$base · ${l10n.agentActionsTriggerSummaryTimeZone(ianaId)}';

  if (trigger.isTemporalTrigger && !trigger.schedule.ignoreMissedRuns) {
    return '$withTimezone · ${l10n.agentActionsTriggerSummaryCatchUpEnabled}';
  }

  return withTimezone;
}

String formatAgentActionTriggerLocalDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String agentActionTriggerTypeLabel(AgentActionTriggerType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionTriggerType.manual => l10n.agentActionsTriggerTypeManual,
    AgentActionTriggerType.remote => l10n.agentActionsTriggerTypeRemote,
    AgentActionTriggerType.once => l10n.agentActionsTriggerTypeOnce,
    AgentActionTriggerType.interval => l10n.agentActionsTriggerTypeInterval,
    AgentActionTriggerType.daily => l10n.agentActionsTriggerTypeDaily,
    AgentActionTriggerType.weekly => l10n.agentActionsTriggerTypeWeekly,
    AgentActionTriggerType.monthly => l10n.agentActionsTriggerTypeMonthly,
    AgentActionTriggerType.appStart => l10n.agentActionsTriggerTypeAppStart,
    AgentActionTriggerType.appClose => l10n.agentActionsTriggerTypeAppClose,
  };
}

String? agentActionCorrectiveActionLabel(
  AgentActionCorrectiveActionKind? correctiveAction,
  AppLocalizations l10n,
) {
  return switch (correctiveAction) {
    AgentActionCorrectiveActionKind.reviewPath => l10n.agentActionsDiagnosticsCorrectivePath,
    AgentActionCorrectiveActionKind.reviewRunner => l10n.agentActionsDiagnosticsCorrectiveRunner,
    AgentActionCorrectiveActionKind.reviewExitCode => l10n.agentActionsDiagnosticsCorrectiveExitCode,
    AgentActionCorrectiveActionKind.reviewQueue => l10n.agentActionsDiagnosticsCorrectiveQueue,
    AgentActionCorrectiveActionKind.reviewTimeout => l10n.agentActionsDiagnosticsCorrectiveTimeout,
    AgentActionCorrectiveActionKind.retryKill => l10n.agentActionsDiagnosticsCorrectiveKill,
    AgentActionCorrectiveActionKind.reviewDefinitionValidation =>
      l10n.agentActionsDiagnosticsCorrectiveDefinitionValidation,
    AgentActionCorrectiveActionKind.reviewPreflight => l10n.agentActionsDiagnosticsCorrectivePreflight,
    AgentActionCorrectiveActionKind.reviewStartProcess => l10n.agentActionsDiagnosticsCorrectiveStartProcess,
    AgentActionCorrectiveActionKind.reviewRuntime => l10n.agentActionsDiagnosticsCorrectiveRuntime,
    _ => null,
  };
}

String agentActionTestDiagnosticLabel(String key, AppLocalizations l10n) {
  return switch (key) {
    'engine' => l10n.agentActionsTestPreviewDiagnosticEngine,
    'connection_label' => l10n.agentActionsTestPreviewDiagnosticConnectionLabel,
    'catalog_connection_count' => l10n.agentActionsTestPreviewDiagnosticCatalogCount,
    'used_default_config_path' => l10n.agentActionsTestPreviewDiagnosticDefaultConfig,
    'phase' => l10n.agentActionsDiagnosticsFailurePhase,
    _ => key,
  };
}

String agentActionTestDiagnosticValue(String key, Object? value, AppLocalizations l10n) {
  if (value is bool) {
    return value ? l10n.agentActionsTestPreviewDiagnosticYes : l10n.agentActionsTestPreviewDiagnosticNo;
  }
  if (key == 'phase' && value is String && value.trim().isNotEmpty) {
    return localizeAgentActionFailurePhase(value, l10n);
  }
  return value?.toString() ?? '-';
}

String localizeAgentActionFailurePhase(String phase, AppLocalizations l10n) {
  return switch (phase.trim()) {
    'execution_preflight' => l10n.agentActionsFailurePhaseExecutionPreflight,
    'definition_validation' => l10n.agentActionsFailurePhaseDefinitionValidation,
    'start_process' => l10n.agentActionsFailurePhaseStartProcess,
    'stdin_setup' => l10n.agentActionsFailurePhaseStdinSetup,
    'process_runtime' => l10n.agentActionsFailurePhaseProcessRuntime,
    'process_exit' => l10n.agentActionsFailurePhaseProcessExit,
    'queue' => l10n.agentActionsFailurePhaseQueue,
    'timeout' => l10n.agentActionsFailurePhaseTimeout,
    'authorization' => l10n.agentActionsFailurePhaseAuthorization,
    'validation' => l10n.agentActionsFailurePhaseValidation,
    'lookup' => l10n.agentActionsFailurePhaseLookup,
    'cancel' => l10n.agentActionsFailurePhaseCancel,
    'platform_check' => l10n.agentActionsFailurePhasePlatformCheck,
    'smtp_send' => l10n.agentActionsFailurePhaseSmtpSend,
    'execution_send' => l10n.agentActionsFailurePhaseExecutionSend,
    'elevated_submit' => l10n.agentActionsFailurePhaseElevatedSubmit,
    'bootstrap_reconciliation' => l10n.agentActionsFailurePhaseBootstrapReconciliation,
    _ => agentActionFailurePhaseFallbackLabel(phase),
  };
}

String agentActionFailurePhaseFallbackLabel(String phase) {
  final normalized = phase.trim();
  if (normalized.isEmpty) {
    return phase;
  }

  return normalized
      .split('_')
      .where((segment) => segment.isNotEmpty)
      .map(
        (segment) => '${segment[0].toUpperCase()}${segment.substring(1)}',
      )
      .join(' ');
}
