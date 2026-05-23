/// Builds the `extensions.agentActions` payload for Socket.IO registration.
abstract class IAgentActionsRemoteCapabilityProvider {
  Map<String, dynamic> buildForTransport({
    required List<String> supportedTypes,
    required bool maintenanceModeEnabled,
    required bool maintenanceStrictModeEnabled,
    required bool remoteAdHocEnabled,
    required bool elevatedActionsEnabled,
  });
}
