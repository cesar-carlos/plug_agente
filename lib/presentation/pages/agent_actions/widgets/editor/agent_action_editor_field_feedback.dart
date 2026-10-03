import 'package:flutter/widgets.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_validation.dart';

abstract final class AgentActionEditorFieldFeedback {
  static Map<TextEditingController, String> requiredFields(AgentActionDraft draft, AppLocalizations l10n) {
    final fields = <TextEditingController, String>{draft.identity.name: l10n.agentActionsFormName};
    if (draft.draftKind == AgentActionDraftKind.powerShell) {
      fields[draft.powerShellMode == PowerShellDraftMode.inline
          ? draft.commandLine.command
          : draft.script.path] = draft.powerShellMode == PowerShellDraftMode.inline
          ? l10n.agentActionsFormPowerShellCommand
          : l10n.agentActionsFormPowerShellScriptPath;
      return fields;
    }
    switch (draft.draftType) {
      case AgentActionType.commandLine:
        fields[draft.commandLine.command] = l10n.agentActionsFormCommand;
      case AgentActionType.executable:
        fields[draft.executable.targetPath] = l10n.agentActionsFormExecutablePath;
      case AgentActionType.script:
        fields[draft.script.path] = l10n.agentActionsFormScriptPath;
      case AgentActionType.jar:
        fields[draft.jar.path] = l10n.agentActionsFormJarPath;
      case AgentActionType.email:
        fields.addAll({
          draft.email.smtpProfileId: l10n.agentActionsFormSmtpProfileId,
          draft.email.from: l10n.agentActionsFormEmailFrom,
          draft.email.to: l10n.agentActionsFormEmailTo,
          draft.email.subject: l10n.agentActionsFormEmailSubject,
          draft.email.body: l10n.agentActionsFormEmailBody,
        });
      case AgentActionType.comObject:
        fields.addAll({
          draft.comObject.progId: l10n.agentActionsFormComProgId,
          draft.comObject.memberName: l10n.agentActionsFormComMemberName,
        });
      case AgentActionType.developer:
        fields.addAll({
          draft.developer.executorPath: l10n.agentActionsFormExecutorPath,
          draft.developer.projectPath: l10n.agentActionsFormProjectPath,
          draft.developer.connectionId: l10n.agentActionsFormConnectionId,
        });
    }
    return fields;
  }

  static List<TextEditingController> controllersFor(AgentActionDraft draft, DraftValidationField field) =>
      switch (field) {
        DraftValidationField.requiredFields ||
        DraftValidationField.preflightActiveState ||
        DraftValidationField.remoteApproval ||
        DraftValidationField.powerShellMode => [],
        DraftValidationField.acceptedExitCodes => [draft.executionPolicy.acceptedExitCodes],
        DraftValidationField.contextSchema => [draft.executionPolicy.runtimeParameterSchema],
        DraftValidationField.environment => [
          draft.executionPolicy.environmentVariables,
          draft.executionPolicy.allowedEnvironmentVariableNames,
        ],
        DraftValidationField.queueLimits => [draft.executionPolicy.maxConcurrent, draft.executionPolicy.maxQueued],
        DraftValidationField.maxRuntime => [draft.executionPolicy.maxRuntimeMinutes],
        DraftValidationField.stopTimeOfDay => [draft.executionPolicy.stopTimeOfDay],
        DraftValidationField.waitBeforeKill => [draft.executionPolicy.waitBeforeKillSeconds],
        DraftValidationField.command => [draft.commandLine.command],
        DraftValidationField.executablePath => [draft.executable.targetPath],
        DraftValidationField.scriptPath || DraftValidationField.powerShellScriptPathInvalid => [draft.script.path],
        DraftValidationField.jarPath => [draft.jar.path],
        DraftValidationField.smtpProfileId => [draft.email.smtpProfileId],
        DraftValidationField.emailFrom => [draft.email.from],
        DraftValidationField.emailTo => [draft.email.to],
        DraftValidationField.emailSubject => [draft.email.subject],
        DraftValidationField.emailBody => [draft.email.body],
        DraftValidationField.comProgId => [draft.comObject.progId],
        DraftValidationField.comMemberName => [draft.comObject.memberName],
        DraftValidationField.comArguments => [draft.comObject.arguments],
        DraftValidationField.executorPath => [draft.developer.executorPath],
        DraftValidationField.projectPath => [draft.developer.projectPath],
        DraftValidationField.connectionId => [draft.developer.connectionId],
      };

  static int sectionFor(DraftValidationField field) => switch (field) {
    DraftValidationField.requiredFields || DraftValidationField.preflightActiveState => 0,
    DraftValidationField.maxRuntime ||
    DraftValidationField.stopTimeOfDay ||
    DraftValidationField.waitBeforeKill ||
    DraftValidationField.acceptedExitCodes => 2,
    DraftValidationField.contextSchema ||
    DraftValidationField.environment ||
    DraftValidationField.queueLimits ||
    DraftValidationField.remoteApproval => 3,
    _ => 1,
  };
}
