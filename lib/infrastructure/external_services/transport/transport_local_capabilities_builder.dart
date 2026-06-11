import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/rpc_batch_negotiation.dart';
import 'package:plug_agente/domain/actions/action_local_runner.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

/// Builds local protocol capabilities advertised during hub negotiation.
final class TransportLocalCapabilitiesBuilder {
  TransportLocalCapabilitiesBuilder({
    required FeatureFlags featureFlags,
    PayloadSigner? payloadSigner,
    IAgentActionsRemoteCapabilityProvider? agentActionsRemoteCapabilityProvider,
    AgentActionLocalRunnerRegistry? agentActionLocalRunnerRegistry,
  }) : _featureFlags = featureFlags,
       _payloadSigner = payloadSigner,
       _agentActionsRemoteCapabilityProvider = agentActionsRemoteCapabilityProvider,
       _agentActionLocalRunnerRegistry = agentActionLocalRunnerRegistry;

  final FeatureFlags _featureFlags;
  final PayloadSigner? _payloadSigner;
  final IAgentActionsRemoteCapabilityProvider? _agentActionsRemoteCapabilityProvider;
  final AgentActionLocalRunnerRegistry? _agentActionLocalRunnerRegistry;

  ProtocolCapabilities? _cached;

  ProtocolCapabilities build() {
    return _cached ??= ProtocolCapabilities.defaultCapabilities(
      binaryPayload: _featureFlags.enableBinaryPayload,
      compressions: _featureFlags.outboundCompressionMode == OutboundCompressionMode.none
          ? const ['none']
          : const ['gzip', 'none'],
      compressionThreshold: _featureFlags.compressionThreshold,
      signatureRequired: localRequiresIncomingSignature,
      signatureAlgorithms: localSignatureAlgorithms,
      streamingResults: _featureFlags.enableSocketStreamingChunks || _featureFlags.enableSocketStreamingFromDb,
      agentActions: _featureFlags.enableAgentActions && _featureFlags.enableRemoteAgentActions
          ? _agentActionsCapability()
          : null,
      parallelBatchDispatch: _featureFlags.enableParallelJsonRpcBatchDispatch
          ? ParallelBatchDispatchNegotiation.agentAdvertisement(enabled: true)
          : null,
    );
  }

  void invalidateCache() {
    _cached = null;
  }

  bool get localShouldSignOutgoing => _featureFlags.enablePayloadSigning && _payloadSigner != null;

  bool get localRequiresIncomingSignature => _featureFlags.requireIncomingPayloadSignatures && _payloadSigner != null;

  List<String> get localSignatureAlgorithms =>
      _payloadSigner == null ? const [] : const [PayloadSigner.supportedAlgorithm];

  Map<String, dynamic> _agentActionsCapability() {
    final provider = _agentActionsRemoteCapabilityProvider;
    if (provider == null) {
      throw StateError(
        'IAgentActionsRemoteCapabilityProvider is required when remote agent actions are enabled.',
      );
    }

    return provider.buildForTransport(
      supportedTypes: _agentActionSupportedTypeNames(),
      maintenanceModeEnabled: _featureFlags.enableAgentActionsMaintenanceMode,
      maintenanceStrictModeEnabled: _featureFlags.enableAgentActionsMaintenanceStrictMode,
      remoteAdHocEnabled: _featureFlags.enableRemoteAdHocAgentActions,
      elevatedActionsEnabled: _featureFlags.enableElevatedAgentActions,
    );
  }

  List<String> _agentActionSupportedTypeNames() {
    final registry = _agentActionLocalRunnerRegistry;
    if (registry == null) {
      return const <String>['commandLine'];
    }
    final names = registry.supportedTypes.map((type) => type.name).toList(growable: false);
    return names.isEmpty ? const <String>['commandLine'] : names;
  }
}
