import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_widgets.dart';

/// The kind of action draft currently being edited.
///
/// Distinct from [AgentActionType] because PowerShell is surfaced as its own
/// editor kind even though it persists as a command line or script action.
enum AgentActionDraftKind {
  commandLine,
  executable,
  script,
  jar,
  email,
  comObject,
  developer,
  powerShell,
}

/// How a PowerShell draft is authored.
enum PowerShellDraftMode {
  inline,
  script,
}

/// Which PowerShell host runs the draft.
enum PowerShellExecutable {
  windowsPowerShell,
  powerShell7,
}

/// Resolves the persisted [AgentActionType] for a draft kind. PowerShell maps to
/// a command line (inline) or a script action depending on [powerShellMode].
AgentActionType agentActionTypeForDraftKind(
  AgentActionDraftKind draftKind,
  PowerShellDraftMode powerShellMode,
) {
  return switch (draftKind) {
    AgentActionDraftKind.commandLine => AgentActionType.commandLine,
    AgentActionDraftKind.executable => AgentActionType.executable,
    AgentActionDraftKind.script => AgentActionType.script,
    AgentActionDraftKind.jar => AgentActionType.jar,
    AgentActionDraftKind.email => AgentActionType.email,
    AgentActionDraftKind.comObject => AgentActionType.comObject,
    AgentActionDraftKind.developer => AgentActionType.developer,
    AgentActionDraftKind.powerShell => switch (powerShellMode) {
      PowerShellDraftMode.inline => AgentActionType.commandLine,
      PowerShellDraftMode.script => AgentActionType.script,
    },
  };
}

String agentActionDraftKindLabel(AgentActionDraftKind draftKind, AppLocalizations l10n) {
  return switch (draftKind) {
    AgentActionDraftKind.commandLine => agentActionEditorTypeLabel(AgentActionType.commandLine, l10n),
    AgentActionDraftKind.executable => agentActionEditorTypeLabel(AgentActionType.executable, l10n),
    AgentActionDraftKind.script => agentActionEditorTypeLabel(AgentActionType.script, l10n),
    AgentActionDraftKind.jar => agentActionEditorTypeLabel(AgentActionType.jar, l10n),
    AgentActionDraftKind.email => agentActionEditorTypeLabel(AgentActionType.email, l10n),
    AgentActionDraftKind.comObject => agentActionEditorTypeLabel(AgentActionType.comObject, l10n),
    AgentActionDraftKind.developer => agentActionEditorTypeLabel(AgentActionType.developer, l10n),
    AgentActionDraftKind.powerShell => l10n.agentActionsTypePowerShell,
  };
}

String powerShellDraftModeLabel(PowerShellDraftMode mode, AppLocalizations l10n) {
  return switch (mode) {
    PowerShellDraftMode.inline => l10n.agentActionsFormPowerShellModeCommand,
    PowerShellDraftMode.script => l10n.agentActionsFormPowerShellModeScript,
  };
}

String powerShellExecutableLabel(PowerShellExecutable executable, AppLocalizations l10n) {
  return switch (executable) {
    PowerShellExecutable.windowsPowerShell => l10n.agentActionsFormPowerShellExecutableWindows,
    PowerShellExecutable.powerShell7 => l10n.agentActionsFormPowerShellExecutablePwsh,
  };
}

String powerShellExecutableName(PowerShellExecutable executable) {
  return switch (executable) {
    PowerShellExecutable.windowsPowerShell => PowerShellCommandLine.windowsPowerShellExecutable,
    PowerShellExecutable.powerShell7 => PowerShellCommandLine.powerShell7Executable,
  };
}
