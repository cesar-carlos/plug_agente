import 'dart:async';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/config/payload_signing_diagnostics.dart';
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
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_heartbeat_bridge.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/query_response_rpc_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_delivery_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_capabilities_lifecycle_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_transport_connection_error_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
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
}

/// Socket.IO transport client for the v2 RPC contract.
class SocketIOTransportClientV2 implements ITransportClient {
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
           ) {
    _localCapabilitiesBuilder = TransportLocalCapabilitiesBuilder(
      featureFlags: _featureFlags,
      payloadSigner: _payloadSigner,
      agentActionsRemoteCapabilityProvider: _agentActionsRemoteCapabilityProvider,
      agentActionLocalRunnerRegistry: _agentActionLocalRunnerRegistry,
    );
    _connectionErrorHandler = SocketIoTransportConnectionErrorHandler(
      resilienceLogPrefix: _resilienceLogPrefix,
      recoveryId: () => _resilienceRecoveryId,
      closeSocket: _closeSocket,
      onTokenExpired: () => _onTokenExpired?.call(),
    );
    _pipelineCache = TransportPipelineCache(
      protocolProvider: () => _currentProtocol,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
      featureFlags: _featureFlags,
      metricsCollector: _protocolMetricsCollector,
    );
    _frameCodec = PayloadFrameCodec(
      pipelineCache: _pipelineCache,
      protocolProvider: () => _currentProtocol,
      localCapabilitiesProvider: _localCapabilitiesBuilder.build,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
      localShouldSignOutgoing: () => _localCapabilitiesBuilder.localShouldSignOutgoing,
      localRequiresIncomingSignature: () => _localCapabilitiesBuilder.localRequiresIncomingSignature,
      payloadSigner: _payloadSigner,
      metricsCollector: _protocolMetricsCollector,
    );
    _responsePreparer = RpcResponsePreparer(
      featureFlags: _featureFlags,
      logSummarizer: _logSummarizer,
      contractValidator: _contractValidator,
      protocolProvider: () => _currentProtocol,
      usesBinaryTransport: () => _usesBinaryTransport,
      agentIdProvider: () => _agentId,
      jsonSchemaValidator: _jsonSchemaValidator,
      schemaCatalog: _schemaCatalog,
      payloadSigner: _payloadSigner,
    );
    _capabilitiesNegotiator = CapabilitiesNegotiator(
      negotiator: _negotiator,
      featureFlags: _featureFlags,
      contractValidator: _contractValidator,
      localCapabilitiesProvider: _localCapabilitiesBuilder.build,
      agentIdProvider: () => _agentId,
      registerProfileProvider: options.registerProfileProvider,
      emit: _emitEventAsync,
      decodeIncoming: _frameCodec.decodeIncoming,
      onTimeoutReconnect: () => _onReconnectionNeeded?.call(),
      payloadSigner: _payloadSigner,
    );
    _authorizationDecisionLogger = AuthorizationDecisionLogger(
      featureFlags: _featureFlags,
      logMessage: _logMessage,
      agentIdProvider: () => _agentId,
      onTokenRefreshRequested: () => _onTokenExpired?.call(),
    );
    _streamPullHandler = RpcStreamPullHandler(
      featureFlags: _featureFlags,
      frameCodec: _frameCodec,
      contractValidator: _contractValidator,
      protocolProvider: () => _currentProtocol,
      emitEventAsync: _emitEventAsync,
      logMessage: _logMessage,
    );
    _inboundHandler = RpcInboundHandler(
      featureFlags: _featureFlags,
      protocolProvider: () => _currentProtocol,
      agentIdProvider: () => _agentId,
      frameCodec: _frameCodec,
      logSummarizer: _logSummarizer,
      responsePreparer: _responsePreparer,
      authorizationDecisionLogger: _authorizationDecisionLogger,
      dispatcher: _rpcDispatcher,
      requestGuard: _rpcRequestGuard,
      schemaValidator: _schemaValidator,
      streamEmitterFactory: _streamPullHandler.createStreamEmitter,
      emitRpcResponse: _emitRpcResponse,
      emitRpcResponseWithMethodContext: _emitRpcResponse,
      emitEvent: _emitEventVoid,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
      jsonSchemaValidator: _jsonSchemaValidator,
      schemaCatalog: _schemaCatalog,
      metricsCollector: _metricsCollector,
      // Must stay late-bound: WebSocketLogProvider registers the handler after construction.
      setHubSqlDashboardCapturePaused: (bool paused) {
        _hubSqlDashboardCapturePauseHandler?.call(paused);
      },
    );
    _rpcResponseDeliveryCoordinator = RpcResponseDeliveryCoordinator(
      responsePreparer: _responsePreparer,
      prepareOutgoingPayload: _prepareOutgoingPayloadAsync,
      logMessage: _logMessage,
      deliveryGuaranteesEnabled: () => _featureFlags.enableSocketDeliveryGuarantees,
      activeSocket: () => _socket,
      connectGeneration: () => _connectGeneration,
      metricsCollector: _metricsCollector,
      emitInternalErrorResponse: _emitInternalErrorResponse,
      onValidatedPayload: _publishLargeResponseAdvice,
    );
    _capabilitiesLifecycleHandler = SocketIoCapabilitiesLifecycleHandler(
      pipelineCache: _pipelineCache,
      commitProtocol: (protocol) => _currentProtocol = protocol,
      currentProtocol: () => _currentProtocol,
      agentId: () => _agentId,
      resilienceLogPrefix: _resilienceLogPrefix,
      supportsProtocolReadyAck: _supportsProtocolReadyAck,
      emitAgentReady: _emitAgentReady,
      startHeartbeat: _heartbeat.start,
      stopHeartbeat: _heartbeat.stop,
      notifyHubLifecycle: (notification) => _onHubLifecycle?.call(notification),
      onNegotiationFailureReconnect: () {
        _closeSocket();
        _onReconnectionNeeded?.call();
      },
      publishPayloadSigningDiagnostic: _publishPayloadSigningDiagnostic,
    );
    _socketEventBinder = TransportSocketEventBinder(
      featureFlags: _featureFlags,
      inboundHandler: _inboundHandler,
      capabilitiesNegotiator: _capabilitiesNegotiator,
      streamPullHandler: _streamPullHandler,
      logMessage: _logMessage,
      agentIdProvider: () => _agentId,
      resilienceLogPrefixProvider: _resilienceLogPrefix,
      connectGenerationProvider: () => _connectGeneration,
      isStaleConnectGeneration: (generation) => generation != _connectGeneration,
      onAuthorizationSessionReset: _authorizationDecisionLogger.resetSessionState,
      onHeartbeatResetTransient: _heartbeat.resetTransientState,
      onTransportConnectedRegister: _capabilitiesNegotiator.sendRegisterAndStartTimeout,
      onHeartbeatStop: _heartbeat.stop,
      onCloseSocket: _closeSocket,
      onConnectError: _handleConnectionError,
      onSocketError: _handleSocketError,
      onDisconnect: _handleDisconnect,
      onCapabilitiesEnvelope: _handleCapabilitiesNegotiation,
      onHeartbeatAck: _heartbeatBridge.handleHeartbeatAck,
      onReconnectionNeeded: () => _onReconnectionNeeded?.call(),
      onHubLifecycle: (notification) => _onHubLifecycle?.call(notification),
      hasMessageCallback: () => _onMessage != null,
      sendReRegisterAfterReconnect: _capabilitiesNegotiator.sendReRegisterAfterReconnect,
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
  late final TransportPipelineCache _pipelineCache;
  late final PayloadFrameCodec _frameCodec;
  late final RpcResponsePreparer _responsePreparer;
  late final CapabilitiesNegotiator _capabilitiesNegotiator;
  late final AuthorizationDecisionLogger _authorizationDecisionLogger;
  late final RpcStreamPullHandler _streamPullHandler;
  late final RpcInboundHandler _inboundHandler;
  late final RpcResponseDeliveryCoordinator _rpcResponseDeliveryCoordinator;
  late final SocketIoCapabilitiesLifecycleHandler _capabilitiesLifecycleHandler;
  late final TransportSocketEventBinder _socketEventBinder;
  late final TransportLocalCapabilitiesBuilder _localCapabilitiesBuilder;
  late final SocketIoTransportConnectionErrorHandler _connectionErrorHandler;

  io.Socket? _socket;
  int _connectGeneration = 0;
  String? _resilienceRecoveryId;
  String _resilienceLogPrefix() {
    final id = _resilienceRecoveryId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return 'recovery_id=$id ';
  }

  String _agentId = '';
  ProtocolConfig _currentProtocol = const ProtocolConfig(
    protocol: 'jsonrpc-v2',
    encoding: 'json',
    compression: 'none',
  );

  void Function(String direction, String event, dynamic data)? _onMessage;
  void Function()? _onTokenExpired;
  void Function()? _onReconnectionNeeded;
  void Function(HubLifecycleNotification)? _onHubLifecycle;
  late final SocketIoHeartbeatController _heartbeat = SocketIoHeartbeatController(
    isConnected: () => _socket?.connected ?? false,
    emitHeartbeat: _emitAgentHeartbeatViaBridge,
    logMessage: _logHeartbeatEventViaBridge,
    onConnectionStale: () => _onReconnectionNeeded?.call(),
  );
  late final SocketIoTransportHeartbeatBridge _heartbeatBridge = SocketIoTransportHeartbeatBridge(
    heartbeat: _heartbeat,
    agentIdProvider: () => _agentId,
    protocolNameProvider: () => _currentProtocol.protocol,
    emitEvent: _emitEvent,
    logMessage: _logMessage,
    decodeIncomingPayload: _decodeIncomingPayloadOrThrow,
  );
  final RpcRequestGuard _rpcRequestGuard = RpcRequestGuard();
  final RpcRequestSchemaValidator _schemaValidator = const RpcRequestSchemaValidator();
  final RpcContractValidator _contractValidator = const RpcContractValidator();
  final LogRateLimiter _diagnosticLogLimiter = LogRateLimiter();

  @override
  void setMessageCallback(
    void Function(String direction, String event, dynamic data)? callback,
  ) {
    _onMessage = callback;
  }

  void Function(bool paused)? _hubSqlDashboardCapturePauseHandler;

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

  void _logMessage(String direction, String event, dynamic data) {
    final onMessage = _onMessage;
    if (onMessage == null) {
      return;
    }
    final compacted = SqlRpcLogPayloadCompactor.compactSocketLogPayload(event, data);
    final traced = _featureFlags.enableSocketSummarizeLargePayloadLogs && compacted != null
        ? _logSummarizer.summarize(direction, event, compacted)
        : compacted;
    scheduleMicrotask(() => onMessage(direction, event, traced));
  }

  bool get _hasReceivedCapabilities => _capabilitiesNegotiator.hasReceivedCapabilities;

  bool get _usesBinaryTransport {
    if (!_hasReceivedCapabilities) {
      return _featureFlags.enableBinaryPayload;
    }
    return _currentProtocol.usesBinaryPayload && _currentProtocol.usesTransportFrame;
  }

  Future<void> _emitRpcResponse(
    dynamic responseData, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) {
    return _rpcResponseDeliveryCoordinator.emit(
      responseData,
      methodsById: methodsById,
    );
  }

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  String get agentId => _agentId;

  @override
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    final connectGeneration = ++_connectGeneration;
    try {
      if (!_featureFlags.enableBinaryPayload) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Binary PayloadFrame transport is required by the current socket contract.',
            context: {'operation': 'connect', 'feature': 'enableBinaryPayload'},
          ),
        );
      }

      _heartbeat.stop();

      _closeSocket();

      _agentId = agentId;
      _capabilitiesNegotiator.reset();
      _currentProtocol = const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
      );
      _publishPayloadSigningDiagnostic('connect_start');

      _socket = _dataSource.createSocket(serverUrl, authToken: authToken);

      final completer = Completer<Result<void>>();
      Timer? timeoutTimer;

      _socketEventBinder.bind(
        socket: _socket!,
        connectGeneration: connectGeneration,
        connectCompleter: completer,
        cancelConnectTimeout: () => timeoutTimer?.cancel(),
      );

      _socket!.connect();

      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_started '
        'agent_id=$_agentId',
      );

      timeoutTimer = Timer(
        const Duration(
          milliseconds: ConnectionConstants.socketConnectionTimeoutMs,
        ),
        () {
          if (!completer.isCompleted) {
            AppLogger.warning(
              'resilience: ${_resilienceLogPrefix()}socket_transport event=initial_connect_timeout '
              'timeout_ms=${ConnectionConstants.socketConnectionTimeoutMs} '
              'agent_id=$_agentId',
            );
            _closeSocket();
            completer.complete(
              Failure(
                _connectionErrorHandler.buildConnectionFailure(
                  'Connection timeout',
                  StateError('Connection timeout'),
                  extraContext: const {
                    'timeout': true,
                    'timeout_stage': 'transport',
                  },
                ),
              ),
            );
          }
        },
      );

      return await completer.future;
    } on Exception catch (e) {
      AppLogger.error(
        'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_exception agent_id=$_agentId',
        e,
      );
      _closeSocket();
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to connect to server',
          cause: e,
          context: {'operation': 'connect'},
        ),
      );
    }
  }

  void _handleDisconnect(dynamic reason) {
    _heartbeat.stop();
    final asString = reason is String ? reason : reason?.toString();
    final serverInitiated = isHubIoServerInitiatedDisconnect(asString);
    final disconnectLine =
        'resilience: ${_resilienceLogPrefix()}socket_transport event=disconnect '
        'kind=${serverInitiated ? "io_server_disconnect" : "client_or_network"} '
        'reason=${asString ?? "unknown"} agent_id=$_agentId '
        '${serverInitiated ? "action=schedule_full_hub_reconnect" : "action=await_transport_reconnect"}';
    if (serverInitiated) {
      AppLogger.warning(disconnectLine);
    } else {
      AppLogger.info(disconnectLine);
    }
    _onHubLifecycle?.call(HubTransportDisconnected(reason: asString));
    if (serverInitiated) {
      _onReconnectionNeeded?.call();
    }
  }

  void _handleCapabilitiesNegotiation(dynamic data) {
    _capabilitiesLifecycleHandler.handle(_capabilitiesNegotiator.handleEnvelope(data));
  }

  void _emitEvent(String event, dynamic logicalPayload) {
    unawaited(
      _emitEventAsync(event, logicalPayload).catchError((Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Unhandled socket emit failure for $event',
          error,
          stackTrace,
        );
        return false;
      }),
    );
  }

  /// Emits [event] after framing [logicalPayload] through the transport
  /// pipeline. Returns `true` when the event was actually emitted; `false`
  /// when the socket is absent or encoding failed (failure is logged as a
  /// warning so callers can react to silent drops — e.g. agent:register).
  Future<bool> _emitEventAsync(String event, dynamic logicalPayload) async {
    final socket = _socket;
    if (socket == null) {
      return false;
    }
    final outgoingResult = await _prepareOutgoingPayloadAsync(
      event,
      logicalPayload,
    );
    if (outgoingResult.isError()) {
      AppLogger.warning(
        '_emitEventAsync: failed to encode $event — frame dropped',
        outgoingResult.exceptionOrNull(),
      );
      return false;
    }
    final outgoingPayload = outgoingResult.getOrThrow();
    try {
      socket.emit(event, outgoingPayload);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Socket emit failed for $event',
        error,
        stackTrace,
      );
      return false;
    }
    _logMessage('SENT', event, logicalPayload);
    return true;
  }

  /// `Future<void>` wrapper for callers that need a void-returning callback
  /// (RpcInboundHandler, RpcStreamPullHandler). Discards the bool result.
  Future<void> _emitEventVoid(String event, dynamic logicalPayload) async {
    await _emitEventAsync(event, logicalPayload);
  }

  Future<Result<Map<String, dynamic>>> _prepareOutgoingPayloadAsync(
    String event,
    dynamic logicalPayload,
  ) async {
    if (!_usesBinaryTransport) {
      AppLogger.error(
        'Attempted to emit $event without negotiated binary PayloadFrame transport',
      );
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Binary PayloadFrame transport is not negotiated',
          context: {
            'event': event,
            'rpc_error_code': RpcErrorCode.internalError,
          },
        ),
      );
    }
    return _frameCodec.prepareOutgoing(
      event: event,
      logicalPayload: logicalPayload,
    );
  }

  void _publishLargeResponseAdvice({
    required String event,
    required dynamic logicalPayload,
  }) {
    if (event != 'rpc:response') {
      return;
    }
    final streamingChunks = _featureFlags.enableSocketStreamingChunks;
    final streamingFromDb = _featureFlags.enableSocketStreamingFromDb;
    final backpressure = _featureFlags.enableSocketBackpressure;
    if (streamingChunks && streamingFromDb && backpressure) {
      return;
    }
    const category = 'large_rpc_response_without_full_streaming';
    // Check the rate limiter BEFORE the O(n) payload tree scan so that once
    // the log budget is exhausted we avoid the scan cost entirely.
    if (!_diagnosticLogLimiter.shouldLog(category)) {
      return;
    }
    if (!jsonTreeLikelyExceedsByteBudget(
      logicalPayload,
      ConnectionConstants.socketOutgoingContractValidationMaxBytes,
    )) {
      return;
    }
    final diagnostic = <String, dynamic>{
      'event': event,
      'threshold_bytes': ConnectionConstants.socketOutgoingContractValidationMaxBytes,
      'streaming_chunks_enabled': streamingChunks,
      'streaming_from_db_enabled': streamingFromDb,
      'backpressure_enabled': backpressure,
      'recommendation': 'Enable DB streaming, rpc:chunk, and rpc:stream.pull backpressure for large result sets.',
      'count': _diagnosticLogLimiter.countFor(category),
    };
    _logMessage('PERFORMANCE', 'rpc:response:large_payload_advice', diagnostic);
    AppLogger.warning(
      'Large rpc:response is being materialized without the full streaming/backpressure path '
      '(count=${_diagnosticLogLimiter.countFor(category)}, '
      'streaming_chunks=$streamingChunks, streaming_from_db=$streamingFromDb, backpressure=$backpressure)',
    );
  }

  dynamic _decodeIncomingPayloadOrThrow(
    dynamic payload, {
    String? sourceEvent,
  }) {
    return _frameCodec.decodeIncoming(payload, sourceEvent: sourceEvent).getOrThrow();
  }

  void _handleConnectionError(
    dynamic error,
    Completer<Result<void>> completer,
  ) => _connectionErrorHandler.handleConnectionError(error, completer);

  void _handleSocketError(dynamic error) => _connectionErrorHandler.handleSocketError(error);

  @override
  Future<Result<void>> disconnect() async {
    try {
      _connectGeneration++;
      // See ITransportClient: do not clear _onTokenExpired / _onReconnectionNeeded /
      // _onHubLifecycle here — recovery reconnects after disconnect and must
      // still receive HubProtocolReady and related lifecycle events.
      _heartbeat.stop();
      _closeSocket();
      _authorizationDecisionLogger.resetSessionState();
      return const Success<Object, Exception>(Object());
    } on Object catch (e) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to disconnect',
          cause: e,
          context: {'operation': 'disconnect'},
        ),
      );
    }
  }

  void _closeSocket() {
    _socketEventBinder.clearSubscriptions();
    _capabilitiesNegotiator.reset();
    _pipelineCache.reset();
    _localCapabilitiesBuilder.invalidateCache();
    // Clear replay cache so hub retries on a new connection (at-least-once
    // delivery) are not blocked by IDs seen on the previous session.
    // Cross-session double-execution is mitigated by the idempotency cache.
    _rpcRequestGuard.clearReplayCache();
    unawaited(
      _rpcDispatcher.cancelActiveStreamOnDisconnect().catchError((Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'Failed to cancel active stream on socket disconnect',
          error,
          stackTrace,
        );
      }),
    );
    final socket = _socket;
    _socket = null;
    _streamPullHandler.dispose();
    _inboundHandler.resetAckBuffer();
    if (socket == null) {
      return;
    }
    socket.disconnect();
    socket.dispose();
  }

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async {
    try {
      if (_socket == null || !_socket!.connected) {
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
            'protocol': _currentProtocol.protocol,
          },
        ),
      );
    }
  }

  /// Sends response using RPC v2 protocol.
  Future<Result<void>> _sendRpcResponse(QueryResponse response) async {
    try {
      final rpcResponse = QueryResponseRpcMapper.toRpcResponse(response);
      await _emitRpcResponse(rpcResponse);

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to send RPC response',
          cause: e,
          context: {'operation': 'sendRpcResponse'},
        ),
      );
    }
  }

  void _emitAgentHeartbeatViaBridge() => _heartbeatBridge.emitAgentHeartbeat();

  void _logHeartbeatEventViaBridge(String direction, String event, dynamic data) =>
      _heartbeatBridge.logHeartbeatEvent(direction, event, data);

  void _emitAgentReady() {
    final payload = <String, dynamic>{
      'agent_id': _agentId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'protocol': _currentProtocol.protocol,
    };
    _emitEvent('agent:ready', payload);
  }

  bool _supportsProtocolReadyAck(ProtocolConfig protocol) {
    final extensionValue = protocol.negotiatedExtensions['protocolReadyAck'];
    return extensionValue is bool && extensionValue;
  }

  void _publishPayloadSigningDiagnostic(String stage) {
    final signer = _payloadSigner;
    final diagnostics = PayloadSigningDiagnostics.evaluate(
      featureFlags: _featureFlags,
      config: _payloadSigningConfig,
    );
    final diagnostic = <String, dynamic>{
      'stage': stage,
      'outgoing_signing_enabled': _featureFlags.enablePayloadSigning,
      'incoming_signature_required_before_negotiation': _featureFlags.requireIncomingPayloadSignatures,
      'signer_configured': signer != null,
      'active_key_id': signer?.activeKeyId,
      'key_count': signer?.keyCount ?? 0,
      'key_source': _payloadSigningConfig.sourceName,
      'secure_storage_available': _payloadSigningConfig.secureStorageAvailable,
      'health': diagnostics.toJson(),
      if (_hasReceivedCapabilities) ...{
        'negotiated_signature_required': _currentProtocol.signatureRequired,
        'negotiated_signature_algorithms': _currentProtocol.signatureAlgorithms,
      },
      if (diagnostics.issues.isNotEmpty) 'warnings': diagnostics.issues.map((issue) => issue.code).toList(),
    };
    _logMessage('SECURITY', 'payload_signing:diagnostic', diagnostic);
    if (diagnostics.hasBlockingIssue && _diagnosticLogLimiter.shouldLog('payload_signing_blocking_issue')) {
      AppLogger.warning(
        'Payload signing configuration has blocking issues '
        '(status=${diagnostics.status.name}, source=${diagnostics.keySource}, '
        'secure_storage=${diagnostics.secureStorageAvailable}, '
        'issues=${diagnostics.issues.map((issue) => issue.code).join(",")})',
      );
    }
  }

  /// Emits a minimal internal-error [rpc:response] so the hub is never left
  /// waiting for a reply when outgoing validation or encoding fails.
  Future<void> _emitInternalErrorResponse(dynamic requestId) async {
    if (_socket == null) return;
    try {
      final errorResponse = RpcResponse.error(
        id: requestId,
        error: RpcError(
          code: RpcErrorCode.internalError,
          message: RpcErrorCode.getMessage(RpcErrorCode.internalError),
        ),
      );
      final prepared = _responsePreparer.prepareForSend(errorResponse);
      final validatedResult = _responsePreparer.validateOutgoing(prepared);
      if (validatedResult.isError()) {
        AppLogger.warning(
          'Fallback rpc:response failed contract validation',
          validatedResult.exceptionOrNull(),
        );
        return;
      }
      final outgoingResult = await _prepareOutgoingPayloadAsync(
        'rpc:response',
        validatedResult.getOrThrow(),
      );
      if (outgoingResult.isError()) {
        AppLogger.warning(
          'Fallback rpc:response could not be framed as PayloadFrame',
          outgoingResult.exceptionOrNull(),
        );
        return;
      }
      final outgoingPayload = outgoingResult.getOrThrow();
      _logMessage('SENT', 'rpc:response', validatedResult.getOrThrow());
      _socket!.emit('rpc:response', outgoingPayload);
    } on Object catch (e, st) {
      AppLogger.warning('Failed to emit fallback internal error response', e, st);
    }
  }
}
