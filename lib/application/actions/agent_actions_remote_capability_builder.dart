import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';

/// Builds the stable `extensions.agentActions` payload announced at Socket.IO registration.
abstract final class AgentActionsRemoteCapabilityBuilder {
  // Shared resolver avoids allocating a new instance per build() call.
  static const AgentOperationalProfileResolver _profileResolver = AgentOperationalProfileResolver();

  static Map<String, dynamic> build({
    required List<String> supportedTypes,
    required String status,
    required bool maintenanceMode,
    required bool maintenanceStrictMode,
    required List<String> unavailableTypes,
    required bool remoteAdHoc,
    required bool elevatedAllowed,
    required bool supportsElevated,
    String? operationalProfile,
  }) {
    final profile = operationalProfile ?? _profileResolver.currentProfile;
    final limits = AgentActionRpcConstants.remoteAgentActionsLimitsCapability;
    final defaultQueueLimits = AgentActionRpcConstants.remoteAgentActionsDefaultQueueLimitsCapability;

    return <String, dynamic>{
      'enabled': true,
      'version': 1,
      // 'profile' and 'agentEnvironment' carry the same value: 'agentEnvironment'
      // is the canonical field; 'profile' is kept for hub backward compatibility.
      'profile': ?profile,
      'agentEnvironment': ?profile,
      'methods': AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered,
      'supportedMethods': AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered,
      'supportedTypes': supportedTypes,
      'requiresIdempotencyKey': true,
      'supportsCancel': true,
      'supportsContext': false,
      'supportsElevated': supportsElevated,
      'elevatedAllowed': elevatedAllowed,
      'remoteAdHoc': remoteAdHoc,
      'supportsRun': true,
      'supportsValidateRun': true,
      'supportsDryRun': true,
      'supportsGetExecution': true,
      'supportsOutputPaging': true,
      'status': status,
      'maintenanceMode': maintenanceMode,
      'maintenanceStrictMode': maintenanceStrictMode,
      'unavailableTypes': unavailableTypes,
      'authorizationScopes': AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered,
      'maxConcurrentActions': AgentActionPolicyDefaults.maxConcurrentActions,
      'maxQueuedActions': AgentActionPolicyDefaults.maxQueuedActions,
      'defaultQueueLimits': defaultQueueLimits,
      'limits': limits,
      'batchPolicy': AgentActionRpcConstants.remoteAgentActionsBatchPolicyCapability,
    };
  }
}
