import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class AgentActionsRemoteAccessPanel extends StatelessWidget {
  const AgentActionsRemoteAccessPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AgentActionsProvider>(
      builder: (context, provider, _) {
        final editable = provider.isFeatureEnabled && !provider.isMaintenanceMode && !provider.isSavingRemoteAccess;
        final selected = provider.selectedDefinition;
        final connection = context.watch<ConnectionProvider?>();
        return Expander(
          header: Text(l10n.remoteAccessTitle),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.remoteAccessDescription),
              if (provider.isMaintenanceMode) Text(l10n.catalogCheckMaintenance),
              if (connection != null && !connection.isConnected) Text(l10n.catalogCheckConnection),
              if (connection != null && connection.isConnected)
                Text(switch (connection.negotiatedActionIo) {
                  true => l10n.catalogNegotiated,
                  false => l10n.catalogIncompatible,
                  null => l10n.catalogAwaiting,
                }),
              if (selected != null) ...[
                Text(selected.name),
                if (!selected.canRun ||
                    !selected.policies.remote.canRunSavedAction ||
                    !selected.policies.remote.allowFaithfulIo)
                  Text(l10n.remoteCheckApproval),
                if (selected.policies.elevated.runElevated ||
                    const {
                      AgentActionType.commandLine,
                      AgentActionType.email,
                      AgentActionType.comObject,
                    }.contains(selected.type))
                  Text(l10n.catalogCheckExecutor),
                if (!provider.triggers.any(
                  (trigger) =>
                      trigger.actionId == selected.id &&
                      trigger.isEnabled &&
                      trigger.type == AgentActionTriggerType.remote,
                ))
                  Text(l10n.catalogCheckTrigger),
              ],
              const SizedBox(height: 12),
              Text(
                !provider.isRemoteAgentActionsEnabled
                    ? l10n.remoteCheckActions
                    : !provider.isActionIoEnabled
                    ? l10n.remoteCheckIo
                    : !provider.definitions.any(
                        (action) => action.policies.remote.canRunSavedAction && action.policies.remote.allowFaithfulIo,
                      )
                    ? l10n.remoteCheckApproval
                    : l10n.remoteCheckHub,
              ),
              const SizedBox(height: 12),
              ToggleSwitch(
                checked: provider.isRemoteAgentActionsEnabled,
                content: Text(l10n.remoteAccessEnabled),
                onChanged: editable
                    ? (value) => provider.saveRemoteAccess(remote: value, io: provider.isActionIoEnabled)
                    : null,
              ),
              const SizedBox(height: 12),
              ToggleSwitch(
                checked: provider.isActionIoEnabled,
                content: Text(l10n.remoteAccessIo),
                onChanged: editable && (provider.isRemoteAgentActionsEnabled || provider.isActionIoEnabled)
                    ? (value) => provider.saveRemoteAccess(remote: provider.isRemoteAgentActionsEnabled, io: value)
                    : null,
              ),
              const SizedBox(height: 12),
              ToggleSwitch(
                checked: provider.isRemoteAdHocAgentActionsEnabled,
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(l10n.remoteAccessAdHoc),
                ),
                onChanged:
                    editable && (provider.isRemoteAgentActionsEnabled || provider.isRemoteAdHocAgentActionsEnabled)
                    ? (value) => provider.saveRemoteAccess(
                        remote: provider.isRemoteAgentActionsEnabled,
                        io: provider.isActionIoEnabled,
                        adHoc: value,
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(l10n.remoteAccessAdHocHelp),
              const SizedBox(height: 12),
              Text(l10n.remoteAccessRestart),
              if (provider.remoteAccessSaveFailed)
                InfoBar(title: Text(l10n.remoteAccessSaveError), severity: InfoBarSeverity.error),
            ],
          ),
        );
      },
    );
  }
}
