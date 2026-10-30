import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_actions_remote_capability_builder.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/domain/protocol/action_io_capability.dart';
import 'package:plug_agente/domain/repositories/i_agent_actions_remote_capability_provider.dart';

class AgentActionsRemoteCapabilityProvider implements IAgentActionsRemoteCapabilityProvider {
  AgentActionsRemoteCapabilityProvider({
    required AgentActionRuntimeStateGuard runtimeStateGuard,
    required ElevatedActionRunnerReadinessService elevatedRunnerReadiness,
    bool Function()? faithfulIoAvailable,
  }) : _runtimeStateGuard = runtimeStateGuard,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _faithfulIoAvailable = faithfulIoAvailable;

  final AgentActionRuntimeStateGuard _runtimeStateGuard;
  final ElevatedActionRunnerReadinessService _elevatedRunnerReadiness;
  final bool Function()? _faithfulIoAvailable;

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
    final unavailableTypes = runtimeSnapshot.unavailableActionTypes.map((type) => type.name).toList(growable: false);

    final capability = AgentActionsRemoteCapabilityBuilder.build(
      supportedTypes: supportedTypes,
      status: status,
      maintenanceMode: maintenanceModeEnabled || status == 'maintenance',
      maintenanceStrictMode: maintenanceStrictModeEnabled,
      unavailableTypes: unavailableTypes,
      remoteAdHoc: remoteAdHocEnabled,
      elevatedAllowed: elevatedActionsEnabled,
      supportsElevated: elevatedActionsEnabled && _elevatedRunnerReadiness.isConfigured,
    );
    if (_faithfulIoAvailable?.call() ?? false) {
      capability['io'] = Map<String, Object>.of(ActionIoCapability.advertisement);
      for (final key in ['methods', 'supportedMethods']) {
        capability[key] = <String>[
          ...(capability[key] as List<String>),
          ...ActionIoCapability.methods,
        ];
      }
      capability['authorizationScopes'] = <String>[
        ...(capability['authorizationScopes'] as List<String>),
        'agent_actions.io',
      ];
    }
    return capability;
  }
}
