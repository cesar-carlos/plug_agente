import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';

abstract final class AgentActionEditorTitles {
  AgentActionEditorTitles._();

  static String createTitle(AgentActionDraftKind draftKind, AppLocalizations l10n) {
    return switch (draftKind) {
      AgentActionDraftKind.commandLine => l10n.agentActionsFormCreateTitle,
      AgentActionDraftKind.executable => l10n.agentActionsFormCreateExecutableTitle,
      AgentActionDraftKind.script => l10n.agentActionsFormCreateScriptTitle,
      AgentActionDraftKind.jar => l10n.agentActionsFormCreateJarTitle,
      AgentActionDraftKind.email => l10n.agentActionsFormCreateEmailTitle,
      AgentActionDraftKind.comObject => l10n.agentActionsFormCreateComObjectTitle,
      AgentActionDraftKind.developer => l10n.agentActionsFormCreateDeveloperTitle,
      AgentActionDraftKind.powerShell => l10n.agentActionsFormCreatePowerShellTitle,
    };
  }

  static String editTitle(AgentActionDraftKind draftKind, AppLocalizations l10n) {
    return switch (draftKind) {
      AgentActionDraftKind.commandLine => l10n.agentActionsFormEditTitle,
      AgentActionDraftKind.executable => l10n.agentActionsFormEditExecutableTitle,
      AgentActionDraftKind.script => l10n.agentActionsFormEditScriptTitle,
      AgentActionDraftKind.jar => l10n.agentActionsFormEditJarTitle,
      AgentActionDraftKind.email => l10n.agentActionsFormEditEmailTitle,
      AgentActionDraftKind.comObject => l10n.agentActionsFormEditComObjectTitle,
      AgentActionDraftKind.developer => l10n.agentActionsFormEditDeveloperTitle,
      AgentActionDraftKind.powerShell => l10n.agentActionsFormEditPowerShellTitle,
    };
  }
}
