import 'dart:async';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/core/utils/sql_rpc_log_payload_compactor.dart';
import 'package:plug_agente/domain/actions/action_local_runner.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/services/i_agent_health_status_provider.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_heartbeat_bridge.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/query_response_rpc_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_connection_lifecycle.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_payload_signing_diagnostic_publisher.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_rpc_pipeline_assembler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_rpc_pipeline_bundle.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:result_dart/result_dart.dart';

part 'socket_io_transport_client_v2_emit.dart';

/// Optional dependencies for [SocketIOTransportClientV2], grouped to reduce
/// constructor arity. All fields are nullable/have defaults; pass a
/// `const SocketIOTransportClientV2Options()` when no optional features are needed.
class SocketIOTransportClientV2Options {
  const SocketIOTransportClientV2Options({
    this.payloadSigner,
    this.payloadSigningConfig,
    this.protocolMetricsCollector,
    this.logSummarizer,
    this.agentActionsRemoteCapabilityProvider,
    this.agentActionLocalRunnerRegistry,
    this.registerProfileProvider,
    this.metricsCollector,
    this.jsonSchemaValidator,
    this.schemaCatalog = const RpcMethodSchemaCatalog(),
    this.healthService,
  });

  final PayloadSigner? payloadSigner;
  final PayloadSigningConfig? payloadSigningConfig;
  final ProtocolMetricsCollector? protocolMetricsCollector;
  final PayloadLogSummarizer? logSummarizer;
  final IAgentActionsRemoteCapabilityProvider? agentActionsRemoteCapabilityProvider;
  final AgentActionLocalRunnerRegistry? agentActionLocalRunnerRegistry;
  final Future<Map<String, dynamic>?> Function()? registerProfileProvider;
  final MetricsCollector? metricsCollector;
  final JsonSchemaContractValidator? jsonSchemaValidator;
  final RpcMethodSchemaCatalog schemaCatalog;
  final IAgentHealthStatusProvider? healthService;
}

/// Socket.IO transport client for the v2 RPC contract.
final class SocketIOTransportClientV2 extends _SocketIoTransportHost
    with _SocketIoTransportEmit
    implements ITransportClient {
  SocketIOTransportClientV2({
    required SocketDataSource dataSource,
    required IProtocolNegotiator negotiator,
    required IRpcRequestDispatcher rpcDispatcher,
    required FeatureFlags featureFlags,
    SocketIOTransportClientV2Options options = const SocketIOTransportClientV2Options(),
  }) : _dataSource = dataSource,
       _negotiator = negotiator,
       _rpcDispatcher = rpcDispatcher,
       _featureFlags = featureFlags,
       _agentActionsRemoteCapabilityProvider = options.agentActionsRemoteCapabilityProvider,
       _agentActionLocalRunnerRegistry = options.agentActionLocalRunnerRegistry,
       _metricsCollector = options.metricsCollector,
       _jsonSchemaValidator = options.jsonSchemaValidator,
       _schemaCatalog = options.schemaCatalog,
       _payloadSigner = options.payloadSigner,
       _payloadSigningConfig =
           options.payloadSigningConfig ??
           PayloadSigningConfig(
             activeKeyId: options.payloadSigner?.activeKeyId,
             keys: options.payloadSigner == null
                 ? const <String, String>{}
                 : {
                     for (final keyId in options.payloadSigner!.keyIds) keyId: '<configured>',
                   },
           ),
       _protocolMetricsCollector = options.protocolMetricsCollector,
       _logSummarizer =
           options.logSummarizer ??
           PayloadLogSummarizer(
             thresholdBytes: ConnectionConstants.socketLogPayloadSummaryThresholdBytes,
           ),
       _registerProfileProvider = options.registerProfileProvider {
    final localCapabilitiesBuilder = TransportLocalCapabilitiesBuilder(
      featureFlags: _featureFlags,
      payloadSigner: _payloadSigner,
      agentActionsRemoteCapabilityProvider: _agentActionsRemoteCapabilityProvider,
      agentActionLocalRunnerRegistry: _agentActionLocalRunnerRegistry,
    );
    late final TransportRpcPipelineBundle pipeline;
    pipeline = const TransportRpcPipelineAssembler().assemble(
      TransportRpcPipelineAssemblyDeps(
        featureFlags: _featureFlags,
        negotiator: _negotiator,
        rpcDispatcher: _rpcDispatcher,
        logSummarizer: _logSummarizer,
        localCapabilitiesBuilder: localCapabilitiesBuilder,
        payloadSigner: _payloadSigner,
        protocolMetricsCollector: _protocolMetricsCollector,
        metricsCollector: _metricsCollector,
        jsonSchemaValidator: _jsonSchemaValidator,
        schemaCatalog: _schemaCatalog,
        contractValidator: _contractValidator,
        resilienceLogPrefix: _resilienceLogPrefix,
        recoveryId: () => _resilienceRecoveryId,
        closeSocket: () => _lifecycle.closeSocket(),
        onTokenExpired: () => _onTokenExpired?.call(),
        registerProfileProvider: _registerProfileProvider,
        emitEventAsync: _emitEventAsync,
        emitEventVoid: _emitEventVoid,
        emitRpcResponse: _emitRpcResponse,
        prepareOutgoingPayload: _prepareOutgoingPayloadAsync,
        logMessage: _logMessage,
        currentProtocol: () => _lifecycle.currentProtocol,
        agentId: () => _lifecycle.agentId,
        hasReceivedCapabilities: () => pipeline.capabilitiesNegotiator.hasReceivedCapabilities,
        usesBinaryTransport: () => _usesBinaryTransport,
        connectGeneration: () => _lifecycle.connectGeneration,
        activeSocket: () => _lifecycle.socket,
        onReconnectionNeeded: () => _onReconnectionNeeded?.call(),
        onHubLifecycle: (notification) => _onHubLifecycle?.call(notification),
        hasMessageCallback: () => _onMessage != null,
        setHubSqlDashboardCapturePaused: (bool paused) => _hubSqlDashboardCapturePauseHandler?.call(paused),
        commitProtocol: (protocol) => _lifecycle.currentProtocol = protocol,
        supportsProtocolReadyAck: _supportsProtocolReadyAck,
        emitAgentReady: _emitAgentReady,
        startHeartbeat: () => _heartbeat.start(),
        stopHeartbeat: () => _heartbeat.stop(),
        resetHeartbeatTransient: () => _heartbeat.resetTransientState(),
        publishPayloadSigningDiagnostic: _publishPayloadSigningDiagnostic,
        publishLargeResponseAdvice: _publishLargeResponseAdvice,
        emitInternalErrorResponse: _emitInternalErrorResponse,
        onConnectError: _handleConnectionError,
        onSocketError: _handleSocketError,
        onDisconnect: (reason) => _lifecycle.handleDisconnect(reason),
        onCapabilitiesEnvelope: _handleCapabilitiesNegotiation,
        onHeartbeatAck: (data) => _heartbeatBridge.handleHeartbeatAck(data),
        healthService: options.healthService,
      ),
    );
    _pipeline = pipeline;
    _lifecycle = TransportConnectionLifecycle(
      dataSource: _dataSource,
      connectionErrorHandler: pipeline.connectionErrorHandler,
      socketEventBinder: pipeline.socketEventBinder,
      capabilitiesNegotiator: pipeline.capabilitiesNegotiator,
      pipelineCache: pipeline.pipelineCache,
      localCapabilitiesBuilder: pipeline.localCapabilitiesBuilder,
      requestGuard: pipeline.requestGuard,
      inboundHandler: pipeline.inboundHandler,
      streamPullHandler: pipeline.streamPullHandler,
      authorizationDecisionLogger: pipeline.authorizationDecisionLogger,
      rpcDispatcher: _rpcDispatcher,
      heartbeatStop: () => _heartbeat.stop(),
      resilienceLogPrefix: _resilienceLogPrefix,
      onHubLifecycle: (notification) => _onHubLifecycle?.call(notification),
      onReconnectionNeeded: () => _onReconnectionNeeded?.call(),
      publishPayloadSigningDiagnostic: _publishPayloadSigningDiagnostic,
      binaryPayloadEnabled: () => _featureFlags.enableBinaryPayload,
    );
    _heartbeat = SocketIoHeartbeatController(
      isConnected: () => _lifecycle.isConnected,
      emitHeartbeat: _emitAgentHeartbeatViaBridge,
      logMessage: _logHeartbeatEventViaBridge,
      onConnectionStale: () {
        _lifecycle.closeSocket();
        _onReconnectionNeeded?.call();
      },
    );
    _heartbeatBridge = SocketIoTransportHeartbeatBridge(
      heartbeat: _heartbeat,
      agentIdProvider: () => _lifecycle.agentId,
      protocolNameProvider: () => _lifecycle.currentProtocol.protocol,
      emitEventAsync: _emitEventAsync,
      logMessage: _logMessage,
      decodeIncomingPayload: _decodeIncomingPayloadOrThrow,
    );
    _payloadSigningDiagnosticPublisher = TransportPayloadSigningDiagnosticPublisher(
      featureFlags: _featureFlags,
      payloadSigningConfig: _payloadSigningConfig,
      payloadSigner: _payloadSigner,
      diagnosticLogLimiter: _diagnosticLogLimiter,
      logMessage: _logMessage,
    );
  }

  final SocketDataSource _dataSource;
  final IProtocolNegotiator _negotiator;
  final IRpcRequestDispatcher _rpcDispatcher;
  final FeatureFlags _featureFlags;
  final IAgentActionsRemoteCapabilityProvider? _agentActionsRemoteCapabilityProvider;
  final AgentActionLocalRunnerRegistry? _agentActionLocalRunnerRegistry;
  final MetricsCollector? _metricsCollector;
  final JsonSchemaContractValidator? _jsonSchemaValidator;
  final RpcMethodSchemaCatalog _schemaCatalog;
  final PayloadSigner? _payloadSigner;
  final PayloadSigningConfig _payloadSigningConfig;
  final ProtocolMetricsCollector? _protocolMetricsCollector;
  final PayloadLogSummarizer _logSummarizer;
  final Future<Map<String, dynamic>?> Function()? _registerProfileProvider;
  final RpcContractValidator _contractValidator = const RpcContractValidator();
  final LogRateLimiter _diagnosticLogLimiter = LogRateLimiter();

  late final TransportRpcPipelineBundle _pipeline;
  late final TransportConnectionLifecycle _lifecycle;
  late final SocketIoHeartbeatController _heartbeat;
  late final SocketIoTransportHeartbeatBridge _heartbeatBridge;
  late final TransportPayloadSigningDiagnosticPublisher _payloadSigningDiagnosticPublisher;

  String? _resilienceRecoveryId;
  void Function(String direction, String event, dynamic data)? _onMessage;
  void Function()? _onTokenExpired;
  void Function()? _onReconnectionNeeded;
  void Function(HubLifecycleNotification)? _onHubLifecycle;
  void Function(bool paused)? _hubSqlDashboardCapturePauseHandler;

  @override
  FeatureFlags get featureFlags => _featureFlags;

  @override
  PayloadLogSummarizer get logSummarizer => _logSummarizer;

  @override
  void Function(String direction, String event, dynamic data)? get onMessage => _onMessage;

  @override
  TransportRpcPipelineBundle get pipeline => _pipeline;

  @override
  TransportConnectionLifecycle get lifecycle => _lifecycle;

  @override
  bool get usesBinaryTransport => _usesBinaryTransport;

  @override
  LogRateLimiter get diagnosticLogLimiter => _diagnosticLogLimiter;

  String _resilienceLogPrefix() {
    final id = _resilienceRecoveryId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return 'recovery_id=$id ';
  }

  bool get _hasReceivedCapabilities => _pipeline.capabilitiesNegotiator.hasReceivedCapabilities;

  bool get _usesBinaryTransport {
    if (!_hasReceivedCapabilities) {
      return _featureFlags.enableBinaryPayload;
    }
    final protocol = _lifecycle.currentProtocol;
    return protocol.usesBinaryPayload && protocol.usesTransportFrame;
  }

  @override
  void setMessageCallback(
    void Function(String direction, String event, dynamic data)? callback,
  ) {
    _onMessage = callback;
  }

  @override
  void setHubSqlDashboardCapturePauseHandler(void Function(bool paused)? handler) {
    _hubSqlDashboardCapturePauseHandler = handler;
  }

  @override
  void setOnTokenExpired(void Function()? callback) {
    _onTokenExpired = callback;
  }

  @override
  void setOnReconnectionNeeded(void Function()? callback) {
    _onReconnectionNeeded = callback;
  }

  @override
  void setOnHubLifecycle(void Function(HubLifecycleNotification notification)? callback) {
    _onHubLifecycle = callback;
  }

  @override
  void setResilienceLogContext(String? recoveryId) {
    final trimmed = recoveryId?.trim();
    _resilienceRecoveryId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool get isConnected => _lifecycle.isConnected;

  @override
  String get agentId => _lifecycle.agentId;

  @override
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) => _lifecycle.connect(serverUrl, agentId, authToken: authToken);

  @override
  Future<Result<void>> disconnect() => _lifecycle.disconnect();

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async {
    try {
      if (_lifecycle.socket == null || !_lifecycle.isConnected) {
        return Failure(domain.NetworkFailure('Not connected to server'));
      }

      return await _sendRpcResponse(response);
    } on Exception catch (e) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to send response',
          cause: e,
          context: {
            'operation': 'sendResponse',
            'requestId': response.requestId,
            'agentId': response.agentId,
            'protocol': _lifecycle.currentProtocol.protocol,
          },
        ),
      );
    }
  }

  void _handleConnectionError(
    dynamic error,
    Completer<Result<void>> completer,
  ) => _pipeline.connectionErrorHandler.handleConnectionError(error, completer);

  void _handleSocketError(dynamic error) => _pipeline.connectionErrorHandler.handleSocketError(error);

  void _handleCapabilitiesNegotiation(dynamic data) {
    _pipeline.capabilitiesLifecycleHandler.handle(_pipeline.capabilitiesNegotiator.handleEnvelope(data));
  }

  Future<bool> _emitAgentHeartbeatViaBridge() => _heartbeatBridge.emitAgentHeartbeat();

  void _logHeartbeatEventViaBridge(String direction, String event, dynamic data) =>
      _heartbeatBridge.logHeartbeatEvent(direction, event, data);

  void _emitAgentReady() {
    final payload = <String, dynamic>{
      'agent_id': _lifecycle.agentId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'protocol': _lifecycle.currentProtocol.protocol,
    };
    _emitEvent('agent:ready', payload);
  }

  bool _supportsProtocolReadyAck(ProtocolConfig protocol) {
    final extensionValue = protocol.negotiatedExtensions['protocolReadyAck'];
    return extensionValue is bool && extensionValue;
  }

  void _publishPayloadSigningDiagnostic(String stage) {
    _payloadSigningDiagnosticPublisher.publish(
      stage: stage,
      hasReceivedCapabilities: _hasReceivedCapabilities,
      currentProtocol: _lifecycle.currentProtocol,
    );
  }
}
