import 'package:plug_agente/core/constants/agent_action_approval_constants.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_validation.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

/// Outcome of attempting to persist the current editor draft.
///
/// Keeps the editor widget free of the per-kind save orchestration while
/// preserving the existing two-phase behavior: editor-side validation
/// produces a [AgentActionDraftSaveRejected] (shown as a validation
/// message), otherwise the draft is forwarded to the provider and
/// [AgentActionDraftSaveForwarded.persisted] mirrors the provider's own
/// save result (which may still reject, e.g. activating an unvalidated
/// action).
sealed class AgentActionDraftSaveOutcome {
  const AgentActionDraftSaveOutcome();
}

final class AgentActionDraftSaveRejected extends AgentActionDraftSaveOutcome {
  const AgentActionDraftSaveRejected(this.message);

  final String message;
}

final class AgentActionDraftSaveForwarded extends AgentActionDraftSaveOutcome {
  const AgentActionDraftSaveForwarded({required this.persisted});

  final bool persisted;
}

/// Translates an [AgentActionDraft] into the matching
/// `AgentActionsProvider.save*Action` call for its kind.
///
/// This isolates the editor's draft-to-domain mapping (required-field
/// checks, policy assembly, PowerShell wrapping) from the editor widget so
/// the widget keeps only UI concerns. Required-field messages are returned
/// rather than pushed through `setState`, so the caller owns presentation.
class AgentActionDraftSaveCoordinator {
  const AgentActionDraftSaveCoordinator({
    required this.draft,
    required this.provider,
    required this.l10n,
    required this.previousDefinition,
    this.validators = const AgentActionDraftValidators(),
    this.localRemoteApprover = AgentActionApprovalConstants.localUiApprover,
  });

  final AgentActionDraft draft;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionDefinition? previousDefinition;
  final AgentActionDraftValidators validators;
  final String localRemoteApprover;

  /// Persists [draft] using [acceptedExitCodes] already parsed and validated
  /// by the caller.
  Future<AgentActionDraftSaveOutcome> save({required Set<int> acceptedExitCodes}) {
    return switch (draft.draftKind) {
      AgentActionDraftKind.commandLine => _saveCommandLine(acceptedExitCodes),
      AgentActionDraftKind.executable => _saveExecutable(acceptedExitCodes),
      AgentActionDraftKind.script => _saveScript(acceptedExitCodes),
      AgentActionDraftKind.jar => _saveJar(acceptedExitCodes),
      AgentActionDraftKind.email => _saveEmail(acceptedExitCodes),
      AgentActionDraftKind.comObject => _saveComObject(acceptedExitCodes),
      AgentActionDraftKind.developer => _saveDeveloper(acceptedExitCodes),
      AgentActionDraftKind.powerShell => _savePowerShell(acceptedExitCodes),
    };
  }

  AgentActionDraftSaveRejected _requiredField(String fieldLabel) {
    return AgentActionDraftSaveRejected(l10n.formFieldRequired(fieldLabel));
  }

  /// Returns the policy validation message when the draft policies are
  /// invalid, or `null` when they pass.
  String? _policyValidationMessage() {
    final result = validators.validatePolicies(draft, l10n: l10n);
    return result is DraftValidationInvalid ? result.message : null;
  }

  AgentActionRemotePolicy _remotePolicy() => draft.remotePolicy(
        remoteAdHocFeatureEnabled: provider.isRemoteAdHocAgentActionsEnabled,
        localApprover: localRemoteApprover,
        previousDefinition: previousDefinition,
      );

  AgentActionElevatedPolicy _elevatedPolicy() =>
      draft.elevatedPolicy(elevatedFeatureEnabled: provider.isElevatedAgentActionsEnabled);

  List<String> _structuredArguments(String raw) => AgentActionDraftParsers.structuredArguments(raw);

  Future<AgentActionDraftSaveOutcome> _saveCommandLine(Set<int> acceptedExitCodes) async {
    final command = draft.commandLine.command.text.trim();
    if (command.isEmpty) {
      return _requiredField(l10n.agentActionsFormCommand);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final persisted = await provider.saveCommandLineAction(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      command: command,
      workingDirectory: draft.commandLine.workingDirectory.text,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      encodingPolicy: draft.encodingPolicy(),
      capturePolicy: draft.capturePolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  Future<AgentActionDraftSaveOutcome> _saveExecutable(Set<int> acceptedExitCodes) async {
    final executablePath = draft.executable.targetPath.text.trim();
    if (executablePath.isEmpty) {
      return _requiredField(l10n.agentActionsFormExecutablePath);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final persisted = await provider.saveExecutableAction(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      executablePath: executablePath,
      arguments: _structuredArguments(draft.executable.arguments.text),
      workingDirectory: draft.commandLine.workingDirectory.text,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      encodingPolicy: draft.encodingPolicy(),
      capturePolicy: draft.capturePolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  Future<AgentActionDraftSaveOutcome> _saveScript(Set<int> acceptedExitCodes) async {
    final scriptPath = draft.script.path.text.trim();
    if (scriptPath.isEmpty) {
      return _requiredField(l10n.agentActionsFormScriptPath);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final persisted = await provider.saveScriptAction(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      scriptPath: scriptPath,
      interpreterPath: draft.script.interpreterPath.text,
      arguments: _structuredArguments(draft.executable.arguments.text),
      workingDirectory: draft.commandLine.workingDirectory.text,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      encodingPolicy: draft.encodingPolicy(),
      capturePolicy: draft.capturePolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  Future<AgentActionDraftSaveOutcome> _saveJar(Set<int> acceptedExitCodes) async {
    final jarPath = draft.jar.path.text.trim();
    if (jarPath.isEmpty) {
      return _requiredField(l10n.agentActionsFormJarPath);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final persisted = await provider.saveJarAction(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      jarPath: jarPath,
      javaExecutablePath: draft.jar.javaExecutablePath.text,
      arguments: _structuredArguments(draft.executable.arguments.text),
      workingDirectory: draft.commandLine.workingDirectory.text,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      encodingPolicy: draft.encodingPolicy(),
      capturePolicy: draft.capturePolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  Future<AgentActionDraftSaveOutcome> _saveEmail(Set<int> acceptedExitCodes) async {
    final smtpProfileId = draft.email.smtpProfileId.text.trim();
    if (smtpProfileId.isEmpty) {
      return _requiredField(l10n.agentActionsFormSmtpProfileId);
    }

    final from = draft.email.from.text.trim();
    if (from.isEmpty) {
      return _requiredField(l10n.agentActionsFormEmailFrom);
    }

    final to = _structuredArguments(draft.email.to.text);
    if (to.isEmpty) {
      return _requiredField(l10n.agentActionsFormEmailTo);
    }

    final subject = draft.email.subject.text.trim();
    if (subject.isEmpty) {
      return _requiredField(l10n.agentActionsFormEmailSubject);
    }

    final body = draft.email.body.text.trim();
    if (body.isEmpty) {
      return _requiredField(l10n.agentActionsFormEmailBody);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final attachmentPaths = _structuredArguments(draft.email.attachments.text)
        .map(
          (path) => AgentActionPathReference(
            originalPath: path,
            pathChangePolicy: draft.pathChangePolicy,
          ),
        )
        .toList(growable: false);

    final persisted = await provider.saveEmailAction(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      smtpProfileId: smtpProfileId,
      from: from,
      to: to,
      cc: _structuredArguments(draft.email.cc.text),
      bcc: _structuredArguments(draft.email.bcc.text),
      subjectTemplate: subject,
      bodyTemplate: body,
      attachmentPaths: attachmentPaths,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  Future<AgentActionDraftSaveOutcome> _saveComObject(Set<int> acceptedExitCodes) async {
    final progId = draft.comObject.progId.text.trim();
    if (progId.isEmpty) {
      return _requiredField(l10n.agentActionsFormComProgId);
    }

    final memberName = draft.comObject.memberName.text.trim();
    if (memberName.isEmpty) {
      return _requiredField(l10n.agentActionsFormComMemberName);
    }

    final argumentsResult = AgentActionDraftParsers.comObjectArguments(draft.comObject.arguments.text);
    if (argumentsResult == null) {
      return AgentActionDraftSaveRejected(l10n.agentActionsFormInvalidComArguments);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final persisted = await provider.saveComObjectAction(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      progId: progId,
      memberName: memberName,
      arguments: argumentsResult,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  Future<AgentActionDraftSaveOutcome> _saveDeveloper(Set<int> acceptedExitCodes) async {
    final executorPath = draft.developer.executorPath.text.trim();
    if (executorPath.isEmpty) {
      return _requiredField(l10n.agentActionsFormExecutorPath);
    }

    final projectPath = draft.developer.projectPath.text.trim();
    if (projectPath.isEmpty) {
      return _requiredField(l10n.agentActionsFormProjectPath);
    }

    final connectionId = draft.developer.connectionId.text.trim();
    if (connectionId.isEmpty) {
      return _requiredField(l10n.agentActionsFormConnectionId);
    }

    final policyMessage = _policyValidationMessage();
    if (policyMessage != null) {
      return AgentActionDraftSaveRejected(policyMessage);
    }

    final persisted = await provider.saveDeveloperData7Action(
      actionId: draft.editingActionId,
      name: draft.identity.name.text.trim(),
      description: draft.identity.description.text,
      executorPath: executorPath,
      projectPath: projectPath,
      data7ConfigPath: draft.developer.data7ConfigPath.text,
      connectionId: connectionId,
      connectionLabel: draft.developer.connectionLabel.text,
      state: draft.state,
      notificationPolicy: draft.notificationPolicy(),
      retryPolicy: draft.retryPolicy(),
      timeoutPolicy: draft.timeoutPolicy(),
      environmentPolicy: draft.environmentPolicy(),
      exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
      processPolicy: draft.processPolicy(),
      encodingPolicy: draft.encodingPolicy(),
      capturePolicy: draft.capturePolicy(),
      lifecyclePolicy: draft.lifecyclePolicy(),
      remotePolicy: _remotePolicy(),
      elevatedPolicy: _elevatedPolicy(),
      contextPolicy: draft.contextPolicy(),
      pathChangePolicy: draft.pathChangePolicy,
      queuePolicy: draft.queuePolicy(),
      pathPolicy: draft.pathPolicy(),
    );
    return AgentActionDraftSaveForwarded(persisted: persisted);
  }

  bool _isPowerShellModeUnavailable(PowerShellDraftMode mode) {
    return switch (mode) {
      PowerShellDraftMode.inline => provider.isActionTypeUnavailable(AgentActionType.commandLine),
      PowerShellDraftMode.script => provider.isActionTypeUnavailable(AgentActionType.script),
    };
  }

  Future<AgentActionDraftSaveOutcome> _savePowerShell(Set<int> acceptedExitCodes) async {
    if (_isPowerShellModeUnavailable(draft.powerShellMode)) {
      return AgentActionDraftSaveRejected(l10n.agentActionsFormPowerShellModeUnavailable);
    }

    switch (draft.powerShellMode) {
      case PowerShellDraftMode.inline:
        final command = draft.commandLine.command.text.trim();
        if (command.isEmpty) {
          return _requiredField(l10n.agentActionsFormPowerShellCommand);
        }

        final policyMessage = _policyValidationMessage();
        if (policyMessage != null) {
          return AgentActionDraftSaveRejected(policyMessage);
        }

        final persisted = await provider.saveCommandLineAction(
          actionId: draft.editingActionId,
          name: draft.identity.name.text.trim(),
          description: draft.identity.description.text,
          command: PowerShellCommandLine.wrapInlineCommand(
            command,
            executable: powerShellExecutableName(draft.powerShellExecutable),
          ),
          workingDirectory: draft.commandLine.workingDirectory.text,
          state: draft.state,
          notificationPolicy: draft.notificationPolicy(),
          retryPolicy: draft.retryPolicy(),
          timeoutPolicy: draft.timeoutPolicy(),
          environmentPolicy: draft.environmentPolicy(),
          exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
          processPolicy: draft.processPolicy(),
          encodingPolicy: draft.encodingPolicy(),
          capturePolicy: draft.capturePolicy(),
          lifecyclePolicy: draft.lifecyclePolicy(),
          remotePolicy: _remotePolicy(),
          elevatedPolicy: _elevatedPolicy(),
          contextPolicy: draft.contextPolicy(),
          pathChangePolicy: draft.pathChangePolicy,
          queuePolicy: draft.queuePolicy(),
          pathPolicy: draft.pathPolicy(),
        );
        return AgentActionDraftSaveForwarded(persisted: persisted);
      case PowerShellDraftMode.script:
        final scriptPath = draft.script.path.text.trim();
        if (scriptPath.isEmpty) {
          return _requiredField(l10n.agentActionsFormPowerShellScriptPath);
        }
        if (!PowerShellCommandLine.isPowerShellScriptPath(scriptPath)) {
          return AgentActionDraftSaveRejected(l10n.agentActionsFormPowerShellScriptPathInvalid);
        }

        final policyMessage = _policyValidationMessage();
        if (policyMessage != null) {
          return AgentActionDraftSaveRejected(policyMessage);
        }

        final persisted = await provider.saveScriptAction(
          actionId: draft.editingActionId,
          name: draft.identity.name.text.trim(),
          description: draft.identity.description.text,
          scriptPath: scriptPath,
          interpreterPath: draft.powerShellExecutable == PowerShellExecutable.powerShell7
              ? PowerShellCommandLine.powerShell7Executable
              : '',
          arguments: _structuredArguments(draft.executable.arguments.text),
          workingDirectory: draft.commandLine.workingDirectory.text,
          state: draft.state,
          notificationPolicy: draft.notificationPolicy(),
          retryPolicy: draft.retryPolicy(),
          timeoutPolicy: draft.timeoutPolicy(),
          environmentPolicy: draft.environmentPolicy(),
          exitCodePolicy: draft.exitCodePolicy(acceptedExitCodes),
          processPolicy: draft.processPolicy(),
          encodingPolicy: draft.encodingPolicy(),
          capturePolicy: draft.capturePolicy(),
          lifecyclePolicy: draft.lifecyclePolicy(),
          remotePolicy: _remotePolicy(),
          elevatedPolicy: _elevatedPolicy(),
          contextPolicy: draft.contextPolicy(),
          pathChangePolicy: draft.pathChangePolicy,
          queuePolicy: draft.queuePolicy(),
          pathPolicy: draft.pathPolicy(),
        );
        return AgentActionDraftSaveForwarded(persisted: persisted);
    }
  }
}
