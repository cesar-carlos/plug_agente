import 'dart:convert';

import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';

/// Capability flags exposed by the agent actions provider that the
/// mapper needs to honour while loading a persisted definition. Passing
/// them as a small bundle keeps the `applyDefinition` signature stable
/// and isolates the mapper from the live `AgentActionsProvider`.
class AgentActionDraftCapabilities {
  const AgentActionDraftCapabilities({
    required this.remoteAdHocEnabled,
    required this.elevatedEnabled,
  });

  final bool remoteAdHocEnabled;
  final bool elevatedEnabled;
}

/// Side-effect callbacks the mapper triggers while applying or clearing
/// a draft. Kept as injectable functions so the editor can wire them to
/// the live provider and so unit tests can observe them.
class AgentActionDraftMapperHooks {
  const AgentActionDraftMapperHooks({
    required this.clearDeveloperConnections,
    required this.markDirty,
    required this.setDraftKind,
    this.scheduleDeveloperConnectionReload,
  });

  /// Called whenever the mapper needs to flush the live developer
  /// connections cache (typically when switching kinds away from
  /// developer or replacing the draft).
  final void Function() clearDeveloperConnections;

  /// Toggles the draft dirty flag and notifies the editor's external
  /// listener. The mapper does **not** flip dirty during load.
  final void Function(bool value) markDirty;

  /// Updates draft kind, propagating side effects on
  /// [AgentActionDraft.powerShellMode], [AgentActionDraft.draftType] and
  /// the read-only display controllers.
  final void Function(AgentActionDraftKind draftKind) setDraftKind;

  /// Triggered when a developer config is loaded. Resolves the
  /// connection list on the next frame; `null` keeps the legacy
  /// "no reload" behaviour (useful in tests).
  final void Function({
    required AgentActionPathPolicy pathPolicy,
    required String? selectedConnectionId,
  })?
  scheduleDeveloperConnectionReload;
}

/// Maps between `AgentActionDefinition` and the in-memory
/// [AgentActionDraft]. Extracted from the editor's `_loadDefinition` /
/// `_clearDraft` so the translation is a pure function (no
/// `setState`, no `widget.provider`, no `BuildContext`) and therefore
/// trivially testable.
class AgentActionDraftMapper {
  const AgentActionDraftMapper();

  /// Resets the draft to a clean state. When [draftKind] is null the
  /// current `draft.draftKind` is preserved so callers can keep the
  /// active form layout while clearing every field.
  void clear(
    AgentActionDraft draft, {
    required AgentActionDraftMapperHooks hooks,
    AgentActionDraftKind? draftKind,
  }) {
    draft.editingActionId = null;
    hooks.setDraftKind(draftKind ?? draft.draftKind);
    draft.powerShellExecutable = PowerShellExecutable.windowsPowerShell;
    draft.identity.name.clear();
    draft.identity.description.clear();
    draft.commandLine.command.clear();
    draft.commandLine.workingDirectory.clear();
    draft.executable.targetPath.clear();
    draft.executable.arguments.clear();
    draft.script.path.clear();
    draft.script.interpreterPath.clear();
    draft.jar.path.clear();
    draft.jar.javaExecutablePath.clear();
    draft.email.smtpProfileId.clear();
    draft.email.from.clear();
    draft.email.to.clear();
    draft.email.cc.clear();
    draft.email.bcc.clear();
    draft.email.subject.clear();
    draft.email.body.clear();
    draft.email.attachments.clear();
    draft.comObject.progId.clear();
    draft.comObject.memberName.clear();
    draft.comObject.arguments.text = '{}';
    draft.developer.executorPath.clear();
    draft.developer.projectPath.clear();
    draft.developer.data7ConfigPath.clear();
    draft.developer.connectionId.clear();
    draft.developer.connectionLabel.clear();
    draft.state = AgentActionState.needsValidation;
    draft.isDraftModifiedSinceLoad = false;
    hooks.markDirty(false);
    draft.notifyOnSuccess = false;
    draft.notifyOnFailure = false;
    draft.notifyOnTimeout = false;
    draft.maxAttempts = 1;
    draft.allowRemoteRetry = false;
    draft.maxRuntimeMinutes = 30;
    draft.executionPolicy.maxRuntimeMinutes.text = '30';
    draft.killMainProcessOnTimeout = true;
    draft.executionPolicy.allowedProfiles.clear();
    draft.executionPolicy.allowedEnvironmentVariableNames.clear();
    draft.executionPolicy.environmentVariables.clear();
    draft.executionPolicy.acceptedExitCodes.text = '0';
    draft.onAppExit = AgentActionOnAppExitBehavior.killMainProcess;
    draft.processWindowMode = AgentActionProcessWindowMode.normal;
    draft.stdoutEncodingMode = AgentActionOutputEncodingMode.systemConsole;
    draft.stderrEncodingMode = AgentActionOutputEncodingMode.systemConsole;
    draft.captureStdout = true;
    draft.captureStderr = true;
    draft.redactBeforePersisting = true;
    draft.executionPolicy.maxConcurrent.text = '1';
    draft.executionPolicy.maxQueued.text = '100';
    draft.concurrencyBehavior = AgentActionConcurrencyBehavior.enqueue;
    draft.executionPolicy.allowedWorkingDirectories.clear();
    draft.executionPolicy.allowedContextDirectories.clear();
    draft.remoteEnabled = false;
    draft.remoteAdHoc = false;
    draft.remoteApprovalGranted = false;
    draft.runElevated = false;
    draft.validationMessage = null;
    hooks.clearDeveloperConnections();
  }

  /// Applies [definition] onto [draft], or clears it when [definition]
  /// is null. The mapper sets `applyingLoadedDefinition` around the
  /// mutation so the dirty listener does not flip during load — the
  /// editor relies on this exact contract to suppress the
  /// `setState(dirty=true)` cascade during initial load.
  void applyDefinition(
    AgentActionDraft draft,
    AgentActionDefinition? definition, {
    required AgentActionDraftCapabilities capabilities,
    required AgentActionDraftMapperHooks hooks,
  }) {
    draft.validationMessage = null;
    draft.isDraftModifiedSinceLoad = false;
    hooks.markDirty(false);
    draft.applyingLoadedDefinition = true;
    try {
      if (definition == null) {
        clear(draft, hooks: hooks);
        return;
      }
      _applySharedPolicies(draft, definition, capabilities);
      _applyConfig(draft, definition, hooks);
    } finally {
      draft.applyingLoadedDefinition = false;
    }
  }

  void _applySharedPolicies(
    AgentActionDraft draft,
    AgentActionDefinition definition,
    AgentActionDraftCapabilities capabilities,
  ) {
    draft.editingActionId = definition.id;
    draft.identity.name.text = definition.name;
    draft.identity.description.text = definition.description ?? '';
    draft.state = definition.state;

    final notification = definition.policies.notification;
    draft.notifyOnSuccess = notification.notifyOnSuccess;
    draft.notifyOnFailure = notification.notifyOnFailure;
    draft.notifyOnTimeout = notification.notifyOnTimeout;

    final retry = definition.policies.retry;
    draft.maxAttempts = retry.maxAttempts < 1 ? 1 : retry.maxAttempts;
    draft.allowRemoteRetry = retry.allowRemote;

    final timeout = definition.policies.timeout;
    draft.maxRuntimeMinutes = timeout.maxRuntime.inMinutes < 1 ? 1 : timeout.maxRuntime.inMinutes;
    draft.executionPolicy.maxRuntimeMinutes.text = '${draft.maxRuntimeMinutes}';
    draft.killMainProcessOnTimeout = timeout.killMainProcessOnTimeout;

    final environment = definition.policies.environment;
    draft.executionPolicy.allowedProfiles.text = environment.allowedProfiles.join(', ');
    draft.executionPolicy.allowedEnvironmentVariableNames.text = environment.allowedVariableNames.join(', ');
    draft.executionPolicy.environmentVariables.text = AgentActionDraftParsers.formatEnvironmentVariables(
      environment.variables,
    );

    draft.executionPolicy.acceptedExitCodes.text = definition.policies.exitCode.acceptedExitCodes.join(', ');
    draft.onAppExit = definition.policies.lifecycle.onAppExit;
    draft.processWindowMode = definition.policies.process.windowMode;

    final encoding = definition.policies.encoding;
    draft.stdoutEncodingMode = encoding.stdout;
    draft.stderrEncodingMode = encoding.stderr;

    final capture = definition.policies.capture;
    draft.captureStdout = capture.captureStdout;
    draft.captureStderr = capture.captureStderr;
    draft.redactBeforePersisting = capture.redactBeforePersisting;

    final queue = definition.policies.queue;
    draft.executionPolicy.maxConcurrent.text = '${queue.maxConcurrent}';
    draft.executionPolicy.maxQueued.text = '${queue.maxQueued}';
    draft.concurrencyBehavior = queue.concurrencyBehavior;

    final pathPolicy = definition.policies.path;
    draft.executionPolicy.allowedWorkingDirectories.text = pathPolicy.allowedWorkingDirectories.join(', ');
    draft.executionPolicy.allowedContextDirectories.text = pathPolicy.allowedContextDirectories.join(', ');

    final remote = definition.policies.remote;
    draft.remoteEnabled = remote.isEnabled;
    draft.remoteAdHoc = remote.allowAdHoc && capabilities.remoteAdHocEnabled;
    draft.remoteApprovalGranted = remote.approvedAt != null && !remote.requiresReapproval;

    draft.runElevated = definition.policies.elevated.runElevated && capabilities.elevatedEnabled;

    final contextPolicy = definition.policies.context;
    draft.contextInjectionMode = contextPolicy.injectionMode;
    final runtimeSchema = contextPolicy.runtimeParameterSchema;
    draft.executionPolicy.runtimeParameterSchema.text = runtimeSchema == null
        ? ''
        : const JsonEncoder.withIndent('  ').convert(runtimeSchema);
  }

  void _applyConfig(
    AgentActionDraft draft,
    AgentActionDefinition definition,
    AgentActionDraftMapperHooks hooks,
  ) {
    switch (definition.config) {
      case final CommandLineActionConfig config:
        final powerShellCommand = PowerShellCommandLine.tryParseInlineCommand(config.command);
        if (powerShellCommand == null) {
          hooks.setDraftKind(AgentActionDraftKind.commandLine);
          draft.commandLine.command.text = config.command;
        } else {
          draft.powerShellMode = PowerShellDraftMode.inline;
          draft.powerShellExecutable = PowerShellCommandLine.isPowerShell7Executable(powerShellCommand.executable)
              ? PowerShellExecutable.powerShell7
              : PowerShellExecutable.windowsPowerShell;
          hooks.setDraftKind(AgentActionDraftKind.powerShell);
          draft.commandLine.command.text = powerShellCommand.command;
        }
        draft.commandLine.workingDirectory.text = config.workingDirectory?.originalPath ?? '';
        draft.pathChangePolicy = config.workingDirectory?.pathChangePolicy ?? AgentActionPathChangePolicy.failIfChanged;
        _clearNonCommandLineFields(draft);
        hooks.clearDeveloperConnections();
      case final ExecutableActionConfig config:
        hooks.setDraftKind(AgentActionDraftKind.executable);
        draft.commandLine.command.clear();
        draft.executable.targetPath.text = config.executablePath.originalPath;
        draft.executable.arguments.text = config.arguments.join('\n');
        draft.commandLine.workingDirectory.text = config.workingDirectory?.originalPath ?? '';
        _clearNonExecutableFields(draft);
        hooks.clearDeveloperConnections();
      case final ScriptActionConfig config:
        if (PowerShellCommandLine.isPowerShellScriptPath(config.scriptPath.originalPath)) {
          draft.powerShellMode = PowerShellDraftMode.script;
          draft.powerShellExecutable =
              PowerShellCommandLine.isPowerShell7Executable(config.interpreterPath?.originalPath)
              ? PowerShellExecutable.powerShell7
              : PowerShellExecutable.windowsPowerShell;
          hooks.setDraftKind(AgentActionDraftKind.powerShell);
        } else {
          hooks.setDraftKind(AgentActionDraftKind.script);
        }
        draft.commandLine.command.clear();
        draft.executable.targetPath.clear();
        draft.executable.arguments.clear();
        draft.script.path.text = config.scriptPath.originalPath;
        draft.script.interpreterPath.text = config.interpreterPath?.originalPath ?? '';
        draft.executable.arguments.text = config.arguments.join('\n');
        draft.commandLine.workingDirectory.text = config.workingDirectory?.originalPath ?? '';
        _clearNonScriptFields(draft);
        hooks.clearDeveloperConnections();
      case final JarActionConfig config:
        hooks.setDraftKind(AgentActionDraftKind.jar);
        draft.commandLine.command.clear();
        draft.executable.targetPath.clear();
        draft.executable.arguments.clear();
        draft.script.path.clear();
        draft.script.interpreterPath.clear();
        draft.jar.path.text = config.jarPath.originalPath;
        draft.jar.javaExecutablePath.text = config.javaExecutablePath?.originalPath ?? '';
        draft.executable.arguments.text = config.arguments.join('\n');
        draft.commandLine.workingDirectory.text = config.workingDirectory?.originalPath ?? '';
        _clearNonJarFields(draft);
        hooks.clearDeveloperConnections();
      case final EmailActionConfig config:
        hooks.setDraftKind(AgentActionDraftKind.email);
        _clearExecutionFieldsForNonProcess(draft);
        draft.email.smtpProfileId.text = config.smtpProfileId;
        draft.email.from.text = config.from;
        draft.email.to.text = config.to.join('\n');
        draft.email.cc.text = config.cc.join('\n');
        draft.email.bcc.text = config.bcc.join('\n');
        draft.email.subject.text = config.subjectTemplate;
        draft.email.body.text = config.bodyTemplate;
        draft.email.attachments.text = config.attachmentPaths.map((path) => path.originalPath).join('\n');
        _clearDeveloperFields(draft);
        hooks.clearDeveloperConnections();
      case final ComObjectActionConfig config:
        hooks.setDraftKind(AgentActionDraftKind.comObject);
        _clearExecutionFieldsForNonProcess(draft);
        _clearEmailFields(draft);
        draft.comObject.progId.text = config.progId;
        draft.comObject.memberName.text = config.memberName;
        draft.comObject.arguments.text = const JsonEncoder.withIndent('  ').convert(config.arguments);
        _clearDeveloperFields(draft);
        hooks.clearDeveloperConnections();
      case final DeveloperActionConfig config:
        hooks.setDraftKind(AgentActionDraftKind.developer);
        _clearExecutionFieldsForNonProcess(draft);
        _clearEmailFields(draft);
        _clearComObjectFields(draft);
        draft.developer.executorPath.text = config.executorPath.originalPath;
        draft.developer.projectPath.text = config.projectPath.originalPath;
        draft.developer.data7ConfigPath.text = config.data7ConfigPath.originalPath;
        draft.developer.connectionId.text = config.connectionId;
        draft.developer.connectionLabel.text = config.connectionLabel;
        hooks.scheduleDeveloperConnectionReload?.call(
          pathPolicy: definition.policies.path,
          selectedConnectionId: config.connectionId,
        );
    }
  }

  void _clearNonCommandLineFields(AgentActionDraft draft) {
    draft.executable.targetPath.clear();
    draft.executable.arguments.clear();
    draft.script.path.clear();
    draft.script.interpreterPath.clear();
    draft.jar.path.clear();
    draft.jar.javaExecutablePath.clear();
    _clearEmailFields(draft);
    _clearComObjectFields(draft);
    _clearDeveloperFields(draft);
  }

  void _clearNonExecutableFields(AgentActionDraft draft) {
    draft.script.path.clear();
    draft.script.interpreterPath.clear();
    draft.jar.path.clear();
    draft.jar.javaExecutablePath.clear();
    _clearEmailFields(draft);
    _clearComObjectFields(draft);
    _clearDeveloperFields(draft);
  }

  void _clearNonScriptFields(AgentActionDraft draft) {
    draft.jar.path.clear();
    draft.jar.javaExecutablePath.clear();
    _clearEmailFields(draft);
    _clearComObjectFields(draft);
    _clearDeveloperFields(draft);
  }

  void _clearNonJarFields(AgentActionDraft draft) {
    _clearEmailFields(draft);
    _clearComObjectFields(draft);
    _clearDeveloperFields(draft);
  }

  void _clearExecutionFieldsForNonProcess(AgentActionDraft draft) {
    draft.commandLine.command.clear();
    draft.executable.targetPath.clear();
    draft.executable.arguments.clear();
    draft.script.path.clear();
    draft.script.interpreterPath.clear();
    draft.jar.path.clear();
    draft.jar.javaExecutablePath.clear();
    draft.commandLine.workingDirectory.clear();
  }

  void _clearEmailFields(AgentActionDraft draft) {
    draft.email.smtpProfileId.clear();
    draft.email.from.clear();
    draft.email.to.clear();
    draft.email.cc.clear();
    draft.email.bcc.clear();
    draft.email.subject.clear();
    draft.email.body.clear();
    draft.email.attachments.clear();
  }

  void _clearComObjectFields(AgentActionDraft draft) {
    draft.comObject.progId.clear();
    draft.comObject.memberName.clear();
    draft.comObject.arguments.text = '{}';
  }

  void _clearDeveloperFields(AgentActionDraft draft) {
    draft.developer.executorPath.clear();
    draft.developer.projectPath.clear();
    draft.developer.data7ConfigPath.clear();
    draft.developer.connectionId.clear();
    draft.developer.connectionLabel.clear();
  }
}
