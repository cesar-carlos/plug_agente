import 'package:collection/collection.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_developer_editor_section.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_sections.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionEditorDeveloperConnectionCoordinator {
  const AgentActionEditorDeveloperConnectionCoordinator({
    required this.draft,
    required this.provider,
    required this.definition,
    required this.l10n,
    required this.showInlineFeedback,
    required this.isMounted,
    required this.onConnectionSelected,
    required this.onDialogWarning,
  });

  final AgentActionDraft draft;
  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AppLocalizations l10n;
  final bool showInlineFeedback;
  final bool Function() isMounted;
  final void Function(String connectionId) onConnectionSelected;
  final void Function(AgentActionEditorDialogWarning warning) onDialogWarning;

  void scheduleReload({
    required AgentActionPathPolicy pathPolicy,
    required String? selectedConnectionId,
    required void Function(Future<void> Function() reload) runAfterFrame,
  }) {
    runAfterFrame(
      () => reloadDeveloperConnections(
        pathPolicy: pathPolicy,
        selectedConnectionId: selectedConnectionId,
      ),
    );
  }

  Future<void> reloadDeveloperConnections({
    required AgentActionPathPolicy pathPolicy,
    String? selectedConnectionId,
  }) async {
    final actionId = (draft.editingActionId?.trim().isNotEmpty ?? false)
        ? draft.editingActionId!.trim()
        : 'developer-draft';
    await provider.loadDeveloperData7Connections(
      actionId: actionId,
      data7ConfigPath: draft.developer.data7ConfigPath.text,
      selectedConnectionId: selectedConnectionId ?? draft.developer.connectionId.text,
      pathPolicy: pathPolicy,
    );

    if (!isMounted()) {
      return;
    }

    final resolvedPath = provider.resolvedDeveloperData7ConfigPath;
    final typedConfigPath = draft.developer.data7ConfigPath.text.trim();
    if (resolvedPath != null &&
        resolvedPath.isNotEmpty &&
        (typedConfigPath.isEmpty || provider.usedDefaultDeveloperData7ConfigPath)) {
      draft.developer.data7ConfigPath.text = resolvedPath;
    }

    final selectedId = selectedConnectionId ?? draft.developer.connectionId.text.trim();
    final selectedOption = provider.developerConnections.where((option) => option.id == selectedId).firstOrNull;
    if (selectedOption != null) {
      onConnectionSelected(selectedOption.id);
      return;
    }

    if (selectedId.isEmpty && provider.developerConnections.length == 1) {
      onConnectionSelected(provider.developerConnections.single.id);
    }

    if (!showInlineFeedback) {
      final lookupMessage = provider.developerConnectionLookupMessage?.trim();
      if (lookupMessage != null && lookupMessage.isNotEmpty) {
        onDialogWarning(
          AgentActionEditorDialogWarning(
            key: 'developer_connection_lookup',
            title: l10n.agentActionsValidationTitle,
            message: lookupMessage,
          ),
        );
      }
    }

    if (!showInlineFeedback) {
      final connectionWarning = AgentActionDeveloperEditorSectionState.resolveConnectionStatusWarning(
        definition: definition,
        draft: draft,
        provider: provider,
        l10n: l10n,
      );
      if (connectionWarning != null && !connectionWarning.key.startsWith('developer_connection_unknown:')) {
        onDialogWarning(connectionWarning);
      }
    }
  }
}
