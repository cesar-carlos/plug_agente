import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';

/// Sealed result of every draft validator. Replaces the previous
/// pattern where validators returned `bool` and side-effected
/// `_draft.validationMessage` inside `setState`. The editor consumes
/// these results in a single place so the dirty-state mutation is no
/// longer scattered across validation code.
sealed class DraftValidationResult {
  const DraftValidationResult();

  bool get isValid => this is DraftValidationValid;
}

/// Successful validation. Stateless — there is no payload to carry.
final class DraftValidationValid extends DraftValidationResult {
  const DraftValidationValid();
}

/// Validation failure. `field` identifies the editor surface the
/// operator should look at; `message` is already localised.
final class DraftValidationInvalid extends DraftValidationResult {
  const DraftValidationInvalid({required this.field, required this.message});

  final DraftValidationField field;
  final String message;
}

/// Logical buckets that group validation failures by editor surface.
/// Lets the UI highlight the section where the issue lives without
/// having to parse the localised message.
enum DraftValidationField {
  requiredFields,
  acceptedExitCodes,
  contextSchema,
  environment,
  queueLimits,
  remoteApproval,
  preflightActiveState,
  powerShellMode,
  powerShellScriptPathInvalid,
  command,
  executablePath,
  scriptPath,
  jarPath,
  smtpProfileId,
  emailFrom,
  emailTo,
  emailSubject,
  emailBody,
  comProgId,
  comMemberName,
  comArguments,
  executorPath,
  projectPath,
  connectionId,
}

/// Pure validators over [AgentActionDraft]. No `setState`, no
/// `BuildContext`, no provider; the editor calls these and renders the
/// returned message via its own validation channel.
class AgentActionDraftValidators {
  const AgentActionDraftValidators({
    ActionEnvironmentResolver environmentResolver = const ActionEnvironmentResolver(),
  }) : _environmentResolver = environmentResolver;

  final ActionEnvironmentResolver _environmentResolver;

  /// Aggregates the required-fields / accepted exit codes /
  /// remote-approval / preflight check that used to live in `_save`.
  DraftValidationResult validateBeforeSave(
    AgentActionDraft draft, {
    required AppLocalizations l10n,
    required bool canSetActive,
  }) {
    final required = _missingRequiredFieldLabels(draft, l10n);
    if (required.isNotEmpty) {
      return DraftValidationInvalid(
        field: DraftValidationField.requiredFields,
        message: required.map((label) => '- ${l10n.formFieldRequired(label)}').join('\n'),
      );
    }

    final acceptedExitCodes = AgentActionDraftParsers.acceptedExitCodes(
      draft.executionPolicy.acceptedExitCodes.text,
    );
    if (acceptedExitCodes == null) {
      return DraftValidationInvalid(
        field: DraftValidationField.acceptedExitCodes,
        message: l10n.agentActionsFormInvalidExitCodes,
      );
    }

    if (draft.remoteEnabled && !draft.remoteApprovalGranted) {
      return DraftValidationInvalid(
        field: DraftValidationField.remoteApproval,
        message: l10n.agentActionsFormRemoteApprovalRequired,
      );
    }

    if (draft.state == AgentActionState.active && !canSetActive) {
      return DraftValidationInvalid(
        field: DraftValidationField.preflightActiveState,
        message: l10n.agentActionsPreflightRequiredForActive,
      );
    }

    return const DraftValidationValid();
  }

  /// Validates the three policy bundles (context / environment /
  /// queue) the editor used to run before persisting via the provider.
  DraftValidationResult validatePolicies(
    AgentActionDraft draft, {
    required AppLocalizations l10n,
  }) {
    final contextResult = _validateContext(draft, l10n);
    if (contextResult is DraftValidationInvalid) return contextResult;

    final environmentResult = _validateEnvironment(draft, l10n);
    if (environmentResult is DraftValidationInvalid) return environmentResult;

    final queueResult = _validateQueue(draft, l10n);
    if (queueResult is DraftValidationInvalid) return queueResult;

    return const DraftValidationValid();
  }

  DraftValidationResult _validateContext(AgentActionDraft draft, AppLocalizations l10n) {
    try {
      draft.contextPolicy();
      return const DraftValidationValid();
    } on FormatException {
      return DraftValidationInvalid(
        field: DraftValidationField.contextSchema,
        message: l10n.agentActionsFormRuntimeParameterSchemaHint,
      );
    }
  }

  DraftValidationResult _validateEnvironment(AgentActionDraft draft, AppLocalizations l10n) {
    try {
      final policy = draft.environmentPolicy();
      final failure = _environmentResolver.validatePolicy(
        actionId: draft.editingActionId ?? 'draft',
        policy: policy,
      );
      if (failure != null) {
        return DraftValidationInvalid(
          field: DraftValidationField.environment,
          message: failure.context['user_message'] as String? ?? failure.message,
        );
      }
      return const DraftValidationValid();
    } on FormatException {
      return DraftValidationInvalid(
        field: DraftValidationField.environment,
        message: l10n.agentActionsFormEnvironmentVariablesInvalid,
      );
    }
  }

  DraftValidationResult _validateQueue(AgentActionDraft draft, AppLocalizations l10n) {
    if (AgentActionDraftParsers.positiveInt(draft.executionPolicy.maxConcurrent.text) == null ||
        AgentActionDraftParsers.positiveInt(draft.executionPolicy.maxQueued.text) == null) {
      return DraftValidationInvalid(
        field: DraftValidationField.queueLimits,
        message: l10n.agentActionsFormInvalidQueueLimits,
      );
    }
    return const DraftValidationValid();
  }

  List<String> _missingRequiredFieldLabels(AgentActionDraft draft, AppLocalizations l10n) {
    final fields = <String>[];
    if (draft.identity.name.text.trim().isEmpty) {
      fields.add(l10n.agentActionsFormName);
    }

    if (draft.draftKind == AgentActionDraftKind.powerShell) {
      switch (draft.powerShellMode) {
        case PowerShellDraftMode.inline:
          if (draft.commandLine.command.text.trim().isEmpty) {
            fields.add(l10n.agentActionsFormPowerShellCommand);
          }
        case PowerShellDraftMode.script:
          if (draft.script.path.text.trim().isEmpty) {
            fields.add(l10n.agentActionsFormPowerShellScriptPath);
          }
      }
      return fields;
    }

    switch (draft.draftType) {
      case AgentActionType.commandLine:
        if (draft.commandLine.command.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormCommand);
        }
      case AgentActionType.executable:
        if (draft.executable.targetPath.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormExecutablePath);
        }
      case AgentActionType.script:
        if (draft.script.path.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormScriptPath);
        }
      case AgentActionType.jar:
        if (draft.jar.path.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormJarPath);
        }
      case AgentActionType.email:
        if (draft.email.smtpProfileId.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormSmtpProfileId);
        }
        if (draft.email.from.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormEmailFrom);
        }
        if (AgentActionDraftParsers.structuredArguments(draft.email.to.text).isEmpty) {
          fields.add(l10n.agentActionsFormEmailTo);
        }
        if (draft.email.subject.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormEmailSubject);
        }
        if (draft.email.body.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormEmailBody);
        }
      case AgentActionType.comObject:
        if (draft.comObject.progId.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormComProgId);
        }
        if (draft.comObject.memberName.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormComMemberName);
        }
      case AgentActionType.developer:
        if (draft.developer.executorPath.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormExecutorPath);
        }
        if (draft.developer.projectPath.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormProjectPath);
        }
        if (draft.developer.connectionId.text.trim().isEmpty) {
          fields.add(l10n.agentActionsFormConnectionId);
        }
    }

    return fields;
  }
}
