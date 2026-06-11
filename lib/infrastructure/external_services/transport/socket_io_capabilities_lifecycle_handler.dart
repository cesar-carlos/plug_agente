import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';

/// Applies negotiated capabilities to transport runtime state and lifecycle hooks.
final class SocketIoCapabilitiesLifecycleHandler {
  SocketIoCapabilitiesLifecycleHandler({
    required TransportPipelineCache pipelineCache,
    required void Function(ProtocolConfig protocol) commitProtocol,
    required ProtocolConfig Function() currentProtocol,
    required String Function() agentId,
    required String Function() resilienceLogPrefix,
    required bool Function(ProtocolConfig protocol) supportsProtocolReadyAck,
    required void Function() emitAgentReady,
    required void Function() startHeartbeat,
    required void Function() stopHeartbeat,
    required void Function(HubLifecycleNotification notification) notifyHubLifecycle,
    required void Function() onNegotiationFailureReconnect,
    required void Function(String stage) publishPayloadSigningDiagnostic,
  }) : _pipelineCache = pipelineCache,
       _commitProtocol = commitProtocol,
       _currentProtocol = currentProtocol,
       _agentId = agentId,
       _resilienceLogPrefix = resilienceLogPrefix,
       _supportsProtocolReadyAck = supportsProtocolReadyAck,
       _emitAgentReady = emitAgentReady,
       _startHeartbeat = startHeartbeat,
       _stopHeartbeat = stopHeartbeat,
       _notifyHubLifecycle = notifyHubLifecycle,
       _onNegotiationFailureReconnect = onNegotiationFailureReconnect,
       _publishPayloadSigningDiagnostic = publishPayloadSigningDiagnostic;

  final TransportPipelineCache _pipelineCache;
  final void Function(ProtocolConfig protocol) _commitProtocol;
  final ProtocolConfig Function() _currentProtocol;
  final String Function() _agentId;
  final String Function() _resilienceLogPrefix;
  final bool Function(ProtocolConfig protocol) _supportsProtocolReadyAck;
  final void Function() _emitAgentReady;
  final void Function() _startHeartbeat;
  final void Function() _stopHeartbeat;
  final void Function(HubLifecycleNotification notification) _notifyHubLifecycle;
  final void Function() _onNegotiationFailureReconnect;
  final void Function(String stage) _publishPayloadSigningDiagnostic;

  void handle(CapabilitiesNegotiationOutcome outcome) {
    switch (outcome) {
      case CapabilitiesNegotiationSuccess(:final negotiatedProtocol, :final wasPostReconnect):
        _commitProtocol(negotiatedProtocol);
        _pipelineCache.clearReceiveCache();

        final limits = _currentProtocol().effectiveLimits;
        AppLogger.info(
          'Protocol negotiated: ${_currentProtocol().protocol}, '
          'encoding: ${_currentProtocol().encoding}, '
          'compression: ${_currentProtocol().compression}, '
          'signature_required: ${_currentProtocol().signatureRequired}, '
          'signature_algorithms: ${_currentProtocol().signatureAlgorithms}, '
          'limits: payload=${limits.maxPayloadBytes}B, '
          'rows=${limits.maxRows}, batch=${limits.maxBatchSize}',
        );
        _publishPayloadSigningDiagnostic('protocol_negotiated');

        if (_supportsProtocolReadyAck(_currentProtocol())) {
          _emitAgentReady();
        }

        _startHeartbeat();

        if (wasPostReconnect) {
          AppLogger.info(
            'resilience: ${_resilienceLogPrefix()}socket_transport event=post_reconnect_capabilities_ok '
            'protocol=${_currentProtocol().protocol} agent_id=${_agentId()}',
          );
          _notifyHubLifecycle(const HubTransportAutoReconnectSucceeded());
        } else {
          _notifyHubLifecycle(const HubProtocolReady());
        }
      case CapabilitiesNegotiationFailure(:final error, :final stackTrace):
        AppLogger.error(
          'resilience: ${_resilienceLogPrefix()}socket_transport event=capabilities_negotiation_failed '
          'agent_id=${_agentId()} - mandatory transport contract rejected',
          error,
          stackTrace,
        );
        _stopHeartbeat();
        _onNegotiationFailureReconnect();
    }
  }
}
