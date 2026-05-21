import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';

/// Builds the stable `extensions.agentActions` payload announced at Socket.IO registration.
abstract final class AgentActionsRemoteCapabilityBuilder {
  static Map<String, dynamic> build({
    required List<String> supportedTypes,
    required String status,
    required bool maintenanceMode,
    required List<String> unavailableTypes,
    required bool remoteAdHoc,
    required bool elevatedAllowed,
    required bool supportsElevated,
    String? operationalProfile,
  }) {
    final profile = operationalProfile ?? const AgentOperationalProfileResolver().currentProfile;
    final limits = AgentActionRpcConstants.remoteAgentActionsLimitsCapability;
    final defaultQueueLimits = AgentActionRpcConstants.remoteAgentActionsDefaultQueueLimitsCapability;

    return <String, dynamic>{
      'enabled': true,
      'version': 1,
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
