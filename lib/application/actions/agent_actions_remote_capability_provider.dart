import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_actions_remote_capability_builder.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/domain/repositories/i_agent_actions_remote_capability_provider.dart';

class AgentActionsRemoteCapabilityProvider implements IAgentActionsRemoteCapabilityProvider {
  AgentActionsRemoteCapabilityProvider({
    required AgentActionRuntimeStateGuard runtimeStateGuard,
    required ElevatedActionRunnerReadinessService elevatedRunnerReadiness,
  }) : _runtimeStateGuard = runtimeStateGuard,
       _elevatedRunnerReadiness = elevatedRunnerReadiness;

  final AgentActionRuntimeStateGuard _runtimeStateGuard;
  final ElevatedActionRunnerReadinessService _elevatedRunnerReadiness;

  @override
  Map<String, dynamic> buildForTransport({
    required List<String> supportedTypes,
    required bool maintenanceModeEnabled,
    required bool maintenanceStrictModeEnabled,
    required bool remoteAdHocEnabled,
    required bool elevatedActionsEnabled,
  }) {
    final runtimeSnapshot = _runtimeStateGuard.snapshot;
    final status = runtimeSnapshot.status.name;
    final unavailableTypes = runtimeSnapshot.unavailableActionTypes
        .map((type) => type.name)
        .toList(growable: false);

    return AgentActionsRemoteCapabilityBuilder.build(
      supportedTypes: supportedTypes,
      status: status,
      maintenanceMode: maintenanceModeEnabled || status == 'maintenance',
      maintenanceStrictMode: maintenanceStrictModeEnabled,
      unavailableTypes: unavailableTypes,
      remoteAdHoc: remoteAdHocEnabled,
      elevatedAllowed: elevatedActionsEnabled,
      supportsElevated: elevatedActionsEnabled && _elevatedRunnerReadiness.isConfigured,
    );
  }
}
