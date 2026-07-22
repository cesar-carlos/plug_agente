import 'dart:async';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/services/i_agent_health_status_provider.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_delivery_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_capabilities_lifecycle_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_transport_connection_error_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_rpc_pipeline_bundle.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_socket_event_binder.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Dependencies required to assemble the Socket.IO RPC transport pipeline.
final class TransportRpcPipelineAssemblyDeps {
  const TransportRpcPipelineAssemblyDeps({
    required this.featureFlags,
    required this.negotiator,
    required this.rpcDispatcher,
    required this.logSummarizer,
    required this.localCapabilitiesBuilder,
    required this.payloadSigner,
    required this.protocolMetricsCollector,
    required this.metricsCollector,
    required this.jsonSchemaValidator,
    required this.schemaCatalog,
    required this.contractValidator,
    required this.resilienceLogPrefix,
    required this.recoveryId,
    required this.closeSocket,
    required this.onTokenExpired,
    required this.registerProfileProvider,
    required this.emitEventAsync,
    required this.emitEventVoid,
    required this.emitRpcResponse,
    required this.prepareOutgoingPayload,
    required this.logMessage,
    required this.currentProtocol,
    required this.agentId,
    required this.hasReceivedCapabilities,
    required this.usesBinaryTransport,
    required this.connectGeneration,
    required this.activeSocket,
    required this.onReconnectionNeeded,
    required this.onHubLifecycle,
    required this.hasMessageCallback,
    required this.setHubSqlDashboardCapturePaused,
    required this.commitProtocol,
    required this.supportsProtocolReadyAck,
    required this.emitAgentReady,
    required this.startHeartbeat,
    required this.stopHeartbeat,
    required this.resetHeartbeatTransient,
    required this.publishPayloadSigningDiagnostic,
    required this.publishLargeResponseAdvice,
    required this.emitInternalErrorResponse,
    required this.onConnectError,
    required this.onSocketError,
    required this.onDisconnect,
    required this.onCapabilitiesEnvelope,
    required this.onHeartbeatAck,
    this.healthService,
  });

  final FeatureFlags featureFlags;
  final IProtocolNegotiator negotiator;
  final IRpcRequestDispatcher rpcDispatcher;
  final PayloadLogSummarizer logSummarizer;
  final TransportLocalCapabilitiesBuilder localCapabilitiesBuilder;
  final PayloadSigner? payloadSigner;
  final ProtocolMetricsCollector? protocolMetricsCollector;
  final MetricsCollector? metricsCollector;
  final JsonSchemaContractValidator? jsonSchemaValidator;
  final RpcMethodSchemaCatalog schemaCatalog;
  final RpcContractValidator contractValidator;
  final String Function() resilienceLogPrefix;
  final String? Function() recoveryId;
  final void Function() closeSocket;
  final void Function()? onTokenExpired;
  final Future<Map<String, dynamic>?> Function()? registerProfileProvider;
  final Future<bool> Function(String event, dynamic logicalPayload) emitEventAsync;
  final Future<void> Function(String event, dynamic logicalPayload) emitEventVoid;
  final Future<void> Function(
    dynamic responseData, {
    Map<Object?, String> methodsById,
  })
  emitRpcResponse;
  final Future<Result<Map<String, dynamic>>> Function(String event, dynamic logicalPayload) prepareOutgoingPayload;
  final void Function(String direction, String event, dynamic data) logMessage;
  final ProtocolConfig Function() currentProtocol;
  final String Function() agentId;
  final bool Function() hasReceivedCapabilities;
  final bool Function() usesBinaryTransport;
  final int Function() connectGeneration;
  final io.Socket? Function() activeSocket;
  final void Function()? onReconnectionNeeded;
  final void Function(HubLifecycleNotification notification)? onHubLifecycle;
  final bool Function() hasMessageCallback;
  final void Function(bool paused) setHubSqlDashboardCapturePaused;
  final void Function(ProtocolConfig protocol) commitProtocol;
  final bool Function(ProtocolConfig protocol) supportsProtocolReadyAck;
  final void Function() emitAgentReady;
  final void Function() startHeartbeat;
  final void Function() stopHeartbeat;
  final void Function() resetHeartbeatTransient;
  final void Function(String stage) publishPayloadSigningDiagnostic;
  final void Function({
    required String event,
    required dynamic logicalPayload,
  })
  publishLargeResponseAdvice;
  final Future<void> Function(dynamic requestId) emitInternalErrorResponse;
  final void Function(dynamic error, Completer<Result<void>> completer) onConnectError;
  final void Function(dynamic error) onSocketError;
  final void Function(dynamic reason) onDisconnect;
  final void Function(dynamic data) onCapabilitiesEnvelope;
  final void Function(dynamic data) onHeartbeatAck;
  final IAgentHealthStatusProvider? healthService;
}

/// Builds RPC pipeline collaborators for the Socket.IO transport client.
final class TransportRpcPipelineAssembler {
  const TransportRpcPipelineAssembler();

  TransportRpcPipelineBundle assemble(TransportRpcPipelineAssemblyDeps deps) {
    final connectionErrorHandler = SocketIoTransportConnectionErrorHandler(
      resilienceLogPrefix: deps.resilienceLogPrefix,
      recoveryId: deps.recoveryId,
      closeSocket: deps.closeSocket,
      onTokenExpired: deps.onTokenExpired,
    );
    final pipelineCache = TransportPipelineCache(
      protocolProvider: deps.currentProtocol,
      hasReceivedCapabilities: deps.hasReceivedCapabilities,
      featureFlags: deps.featureFlags,
      metricsCollector: deps.protocolMetricsCollector,
    );
    final frameCodec = PayloadFrameCodec(
      pipelineCache: pipelineCache,
      protocolProvider: deps.currentProtocol,
      localCapabilitiesProvider: deps.localCapabilitiesBuilder.build,
      hasReceivedCapabilities: deps.hasReceivedCapabilities,
      localShouldSignOutgoing: () => deps.localCapabilitiesBuilder.localShouldSignOutgoing,
      localRequiresIncomingSignature: () => deps.localCapabilitiesBuilder.localRequiresIncomingSignature,
      payloadSigner: deps.payloadSigner,
      metricsCollector: deps.protocolMetricsCollector,
    );
    final responsePreparer = RpcResponsePreparer(
      featureFlags: deps.featureFlags,
      logSummarizer: deps.logSummarizer,
      contractValidator: deps.contractValidator,
      protocolProvider: deps.currentProtocol,
      usesBinaryTransport: deps.usesBinaryTransport,
      agentIdProvider: deps.agentId,
      jsonSchemaValidator: deps.jsonSchemaValidator,
      schemaCatalog: deps.schemaCatalog,
      payloadSigner: deps.payloadSigner,
    );
    final capabilitiesNegotiator = CapabilitiesNegotiator(
      negotiator: deps.negotiator,
      featureFlags: deps.featureFlags,
      contractValidator: deps.contractValidator,
      localCapabilitiesProvider: deps.localCapabilitiesBuilder.build,
      agentIdProvider: deps.agentId,
      registerProfileProvider: deps.registerProfileProvider,
      emit: deps.emitEventAsync,
      decodeIncoming: frameCodec.decodeIncoming,
      onTimeoutReconnect: () {
        deps.closeSocket();
        deps.onReconnectionNeeded?.call();
      },
      payloadSigner: deps.payloadSigner,
    );
    final authorizationDecisionLogger = AuthorizationDecisionLogger(
      featureFlags: deps.featureFlags,
      logMessage: deps.logMessage,
      agentIdProvider: deps.agentId,
      onTokenRefreshRequested: () => deps.onTokenExpired?.call(),
    );
    final streamPullHandler = RpcStreamPullHandler(
      featureFlags: deps.featureFlags,
      frameCodec: frameCodec,
      contractValidator: deps.contractValidator,
      protocolProvider: deps.currentProtocol,
      emitEventAsync: deps.emitEventAsync,
      logMessage: deps.logMessage,
      metricsCollector: deps.metricsCollector,
    );
    final requestGuard = RpcRequestGuard();
    const schemaValidator = RpcRequestSchemaValidator();
    final inboundHandler = RpcInboundHandler(
      featureFlags: deps.featureFlags,
      protocolProvider: deps.currentProtocol,
      agentIdProvider: deps.agentId,
      frameCodec: frameCodec,
      logSummarizer: deps.logSummarizer,
      responsePreparer: responsePreparer,
      authorizationDecisionLogger: authorizationDecisionLogger,
      dispatcher: deps.rpcDispatcher,
      requestGuard: requestGuard,
      schemaValidator: schemaValidator,
      streamEmitterFactory: streamPullHandler.createStreamEmitter,
      emitRpcResponse: deps.emitRpcResponse,
      emitRpcResponseWithMethodContext: deps.emitRpcResponse,
      emitEvent: deps.emitEventVoid,
      hasReceivedCapabilities: deps.hasReceivedCapabilities,
      jsonSchemaValidator: deps.jsonSchemaValidator,
      schemaCatalog: deps.schemaCatalog,
      metricsCollector: deps.metricsCollector,
      setHubSqlDashboardCapturePaused: deps.setHubSqlDashboardCapturePaused,
      healthService: deps.healthService,
    );
    final rpcResponseDeliveryCoordinator = RpcResponseDeliveryCoordinator(
      responsePreparer: responsePreparer,
      prepareOutgoingPayload: deps.prepareOutgoingPayload,
      logMessage: deps.logMessage,
      deliveryGuaranteesEnabled: () => deps.featureFlags.enableSocketDeliveryGuarantees,
      activeSocket: deps.activeSocket,
      connectGeneration: deps.connectGeneration,
      metricsCollector: deps.metricsCollector,
      emitInternalErrorResponse: deps.emitInternalErrorResponse,
      onValidatedPayload: deps.publishLargeResponseAdvice,
    );
    final capabilitiesLifecycleHandler = SocketIoCapabilitiesLifecycleHandler(
      pipelineCache: pipelineCache,
      commitProtocol: deps.commitProtocol,
      currentProtocol: deps.currentProtocol,
      agentId: deps.agentId,
      resilienceLogPrefix: deps.resilienceLogPrefix,
      supportsProtocolReadyAck: deps.supportsProtocolReadyAck,
      emitAgentReady: deps.emitAgentReady,
      startHeartbeat: deps.startHeartbeat,
      stopHeartbeat: deps.stopHeartbeat,
      notifyHubLifecycle: (notification) => deps.onHubLifecycle?.call(notification),
      onNegotiationFailureReconnect: () {
        deps.closeSocket();
        deps.onReconnectionNeeded?.call();
      },
      publishPayloadSigningDiagnostic: deps.publishPayloadSigningDiagnostic,
    );
    final socketEventBinder = TransportSocketEventBinder(
      featureFlags: deps.featureFlags,
      inboundHandler: inboundHandler,
      capabilitiesNegotiator: capabilitiesNegotiator,
      streamPullHandler: streamPullHandler,
      logMessage: deps.logMessage,
      agentIdProvider: deps.agentId,
      resilienceLogPrefixProvider: deps.resilienceLogPrefix,
      connectGenerationProvider: deps.connectGeneration,
      isStaleConnectGeneration: (generation) => generation != deps.connectGeneration(),
      onAuthorizationSessionReset: authorizationDecisionLogger.resetSessionState,
      onHeartbeatResetTransient: deps.resetHeartbeatTransient,
      onTransportConnectedRegister: capabilitiesNegotiator.sendRegisterAndStartTimeout,
      onHeartbeatStop: deps.stopHeartbeat,
      onCloseSocket: deps.closeSocket,
      onConnectError: deps.onConnectError,
      onSocketError: deps.onSocketError,
      onDisconnect: deps.onDisconnect,
      onCapabilitiesEnvelope: deps.onCapabilitiesEnvelope,
      onHeartbeatAck: deps.onHeartbeatAck,
      onReconnectionNeeded: deps.onReconnectionNeeded,
      onHubLifecycle: deps.onHubLifecycle,
      hasMessageCallback: deps.hasMessageCallback,
      sendReRegisterAfterReconnect: capabilitiesNegotiator.sendReRegisterAfterReconnect,
    );

    return TransportRpcPipelineBundle(
      localCapabilitiesBuilder: deps.localCapabilitiesBuilder,
      connectionErrorHandler: connectionErrorHandler,
      pipelineCache: pipelineCache,
      frameCodec: frameCodec,
      responsePreparer: responsePreparer,
      capabilitiesNegotiator: capabilitiesNegotiator,
      authorizationDecisionLogger: authorizationDecisionLogger,
      streamPullHandler: streamPullHandler,
      inboundHandler: inboundHandler,
      rpcResponseDeliveryCoordinator: rpcResponseDeliveryCoordinator,
      capabilitiesLifecycleHandler: capabilitiesLifecycleHandler,
      socketEventBinder: socketEventBinder,
      requestGuard: requestGuard,
      schemaValidator: schemaValidator,
      contractValidator: deps.contractValidator,
    );
  }
}
