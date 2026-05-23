import 'dart:async';
import 'dart:convert';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/config/payload_signing_diagnostics.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/actions/action_local_runner.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/delivery_guarantee.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/hub_connect_error_auth_heuristics.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
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

/// Socket.IO transport client for the v2 RPC contract.
class SocketIOTransportClientV2 implements ITransportClient {
  SocketIOTransportClientV2({
    required SocketDataSource dataSource,
    required IProtocolNegotiator negotiator,
    required IRpcRequestDispatcher rpcDispatcher,
    required FeatureFlags featureFlags,
    PayloadSigner? payloadSigner,
    PayloadSigningConfig? payloadSigningConfig,
    ProtocolMetricsCollector? protocolMetricsCollector,
    PayloadLogSummarizer? logSummarizer,
    IAgentActionsRemoteCapabilityProvider? agentActionsRemoteCapabilityProvider,
    AgentActionLocalRunnerRegistry? agentActionLocalRunnerRegistry,
    Future<Map<String, dynamic>?> Function()? registerProfileProvider,
    MetricsCollector? metricsCollector,
    JsonSchemaContractValidator? jsonSchemaValidator,
    RpcMethodSchemaCatalog schemaCatalog = const RpcMethodSchemaCatalog(),
  }) : _dataSource = dataSource,
       _negotiator = negotiator,
       _rpcDispatcher = rpcDispatcher,
       _featureFlags = featureFlags,
       _agentActionsRemoteCapabilityProvider = agentActionsRemoteCapabilityProvider,
       _agentActionLocalRunnerRegistry = agentActionLocalRunnerRegistry,
       _metricsCollector = metricsCollector,
       _jsonSchemaValidator = jsonSchemaValidator,
       _schemaCatalog = schemaCatalog,
       _payloadSigner = payloadSigner,
       _payloadSigningConfig =
           payloadSigningConfig ??
           PayloadSigningConfig(
             activeKeyId: payloadSigner?.activeKeyId,
             keys: payloadSigner == null
                 ? const <String, String>{}
                 : {
                     for (final keyId in payloadSigner.keyIds) keyId: '<configured>',
                   },
           ),
       _protocolMetricsCollector = protocolMetricsCollector,
       _logSummarizer =
           logSummarizer ??
           PayloadLogSummarizer(
             thresholdBytes: ConnectionConstants.socketLogPayloadSummaryThresholdBytes,
           ) {
    _pipelineCache = TransportPipelineCache(
      protocolProvider: () => _currentProtocol,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
      featureFlags: _featureFlags,
      metricsCollector: _protocolMetricsCollector,
    );
    _frameCodec = PayloadFrameCodec(
      pipelineCache: _pipelineCache,
      protocolProvider: () => _currentProtocol,
      localCapabilitiesProvider: _localCapabilities,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
      localShouldSignOutgoing: () => _localShouldSignOutgoing,
      localRequiresIncomingSignature: () => _localRequiresIncomingSignature,
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
      localCapabilitiesProvider: _localCapabilities,
      agentIdProvider: () => _agentId,
      registerProfileProvider: registerProfileProvider,
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
      emitEvent: _emitEventAsync,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
      jsonSchemaValidator: _jsonSchemaValidator,
      schemaCatalog: _schemaCatalog,
      metricsCollector: _metricsCollector,
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
      onHeartbeatAck: _handleHeartbeatAck,
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
  late final TransportSocketEventBinder _socketEventBinder;

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
    emitHeartbeat: _emitAgentHeartbeat,
    logMessage: _logHeartbeatEvent,
    onConnectionStale: () => _onReconnectionNeeded?.call(),
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
    final traced = _featureFlags.enableSocketSummarizeLargePayloadLogs && data != null
        ? _logSummarizer.summarize(direction, event, data)
        : data;
    onMessage(direction, event, traced);
  }

  ProtocolCapabilities _localCapabilities() {
    return ProtocolCapabilities.defaultCapabilities(
      binaryPayload: _featureFlags.enableBinaryPayload,
      compressions: _featureFlags.outboundCompressionMode == OutboundCompressionMode.none
          ? const ['none']
          : const ['gzip', 'none'],
      compressionThreshold: _featureFlags.compressionThreshold,
      signatureRequired: _localRequiresIncomingSignature,
      signatureAlgorithms: _localSignatureAlgorithms,
      streamingResults: _featureFlags.enableSocketStreamingChunks || _featureFlags.enableSocketStreamingFromDb,
      agentActions: _featureFlags.enableAgentActions && _featureFlags.enableRemoteAgentActions
          ? _agentActionsCapability()
          : null,
    );
  }

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
      remoteAdHocEnabled: _featureFlags.enableRemoteAdHocAgentActions,
      elevatedActionsEnabled: _featureFlags.enableElevatedAgentActions,
    );
  }

  /// Types with a registered local runner, aligned with `agent_actions.supported_types` in health payloads.
  List<String> _agentActionSupportedTypeNames() {
    final registry = _agentActionLocalRunnerRegistry;
    if (registry == null) {
      return const <String>['commandLine'];
    }
    final names = registry.supportedTypes.map((type) => type.name).toList(growable: false);
    return names.isEmpty ? const <String>['commandLine'] : names;
  }

  bool get _localShouldSignOutgoing => _featureFlags.enablePayloadSigning && _payloadSigner != null;

  bool get _localRequiresIncomingSignature => _featureFlags.requireIncomingPayloadSignatures && _payloadSigner != null;

  List<String> get _localSignatureAlgorithms =>
      _payloadSigner == null ? const [] : const [PayloadSigner.supportedAlgorithm];

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
  }) async {
    final prepared = responseData is List<RpcResponse>
        ? responseData.map(_responsePreparer.prepareForSend).toList()
        : _responsePreparer.prepareForSend(responseData as RpcResponse);
    final validatedResult = _responsePreparer.validateOutgoing(
      prepared,
      methodsById: methodsById,
    );
    if (validatedResult.isError()) {
      AppLogger.warning(
        'rpc:response outgoing validation failed catastrophically - emitting internal error',
        validatedResult.exceptionOrNull(),
      );
      final requestId = _extractResponseId(responseData);
      await _emitInternalErrorResponse(requestId);
      return;
    }
    final validatedPayload = validatedResult.getOrThrow();
    _publishLargeResponseAdvice(
      event: 'rpc:response',
      logicalPayload: validatedPayload,
    );
    final outgoingResult = await _prepareOutgoingPayloadAsync(
      'rpc:response',
      validatedPayload,
    );
    if (outgoingResult.isError()) {
      AppLogger.warning(
        'rpc:response pipeline encoding failed - emitting internal error',
        outgoingResult.exceptionOrNull(),
      );
      final requestId = _extractResponseId(responseData);
      await _emitInternalErrorResponse(requestId);
      return;
    }
    final outgoingPayload = outgoingResult.getOrThrow();

    if (!_featureFlags.enableSocketDeliveryGuarantees || _socket == null) {
      _logMessage('SENT', 'rpc:response', validatedPayload);
      _socket?.emit('rpc:response', outgoingPayload);
      return;
    }

    // Total send attempts: 1 initial + maxResponseRetries.
    // After all attempts fail, fall back to fire-and-forget emit so the hub
    // still receives the response (best-effort) instead of nothing at all.
    const maxRetries = DeliveryGuaranteeConfig.maxResponseRetries;
    final timeoutMs = DeliveryGuaranteeConfig.responseAckTimeout.inMilliseconds;
    const totalAttempts = maxRetries + 1;

    for (var attempt = 0; attempt < totalAttempts; attempt++) {
      try {
        _logMessage('SENT', 'rpc:response', validatedPayload);
        await _socket!.timeout(timeoutMs).emitWithAckAsync('rpc:response', outgoingPayload);
        return;
      } on Exception catch (e) {
        final remaining = totalAttempts - attempt - 1;
        if (remaining > 0) {
          AppLogger.warning(
            'rpc:response ack timeout, retrying (${attempt + 1}/$maxRetries)',
            e,
          );
        } else {
          AppLogger.warning(
            'rpc:response ack failed after $maxRetries retries, sending without ack',
            e,
          );
          _socket?.emit('rpc:response', outgoingPayload);
        }
      }
    }
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
                _buildConnectionFailure(
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
    unawaited(_rpcDispatcher.cancelActiveStreamOnDisconnect());
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
    final outcome = _capabilitiesNegotiator.handleEnvelope(data);
    switch (outcome) {
      case CapabilitiesNegotiationSuccess(:final negotiatedProtocol, :final wasPostReconnect):
        _currentProtocol = negotiatedProtocol;
        _pipelineCache.clearReceiveCache();

        final limits = _currentProtocol.effectiveLimits;
        AppLogger.info(
          'Protocol negotiated: ${_currentProtocol.protocol}, '
          'encoding: ${_currentProtocol.encoding}, '
          'compression: ${_currentProtocol.compression}, '
          'signature_required: ${_currentProtocol.signatureRequired}, '
          'signature_algorithms: ${_currentProtocol.signatureAlgorithms}, '
          'limits: payload=${limits.maxPayloadBytes}B, '
          'rows=${limits.maxRows}, batch=${limits.maxBatchSize}',
        );
        _publishPayloadSigningDiagnostic('protocol_negotiated');

        if (_supportsProtocolReadyAck()) {
          _emitAgentReady();
        }

        _heartbeat.start();

        if (wasPostReconnect) {
          AppLogger.info(
            'resilience: ${_resilienceLogPrefix()}socket_transport event=post_reconnect_capabilities_ok '
            'protocol=${_currentProtocol.protocol} agent_id=$_agentId',
          );
          _onHubLifecycle?.call(const HubTransportAutoReconnectSucceeded());
        } else {
          _onHubLifecycle?.call(const HubProtocolReady());
        }
      case CapabilitiesNegotiationFailure(:final error, :final stackTrace):
        AppLogger.error(
          'resilience: ${_resilienceLogPrefix()}socket_transport event=capabilities_negotiation_failed '
          'agent_id=$_agentId - mandatory transport contract rejected',
          error,
          stackTrace,
        );
        _heartbeat.stop();
        _closeSocket();
        _onReconnectionNeeded?.call();
    }
  }

  void _emitEvent(String event, dynamic logicalPayload) {
    unawaited(_emitEventAsync(event, logicalPayload));
  }

  Future<void> _emitEventAsync(String event, dynamic logicalPayload) async {
    if (_socket == null) {
      return;
    }
    final outgoingResult = await _prepareOutgoingPayloadAsync(
      event,
      logicalPayload,
    );
    if (outgoingResult.isError()) {
      return;
    }
    final outgoingPayload = outgoingResult.getOrThrow();
    _logMessage('SENT', event, logicalPayload);
    _socket!.emit(event, outgoingPayload);
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
    if (!jsonTreeLikelyExceedsByteBudget(
      logicalPayload,
      ConnectionConstants.socketOutgoingContractValidationMaxBytes,
    )) {
      return;
    }
    final streamingChunks = _featureFlags.enableSocketStreamingChunks;
    final streamingFromDb = _featureFlags.enableSocketStreamingFromDb;
    final backpressure = _featureFlags.enableSocketBackpressure;
    if (streamingChunks && streamingFromDb && backpressure) {
      return;
    }
    const category = 'large_rpc_response_without_full_streaming';
    if (!_diagnosticLogLimiter.shouldLog(category)) {
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
  ) {
    final structured = _parseStructuredErrorPayload(error);
    final errorMessage = structured?.message ?? error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = _buildConnectionFailure(
      errorMessage,
      errorObj,
      structured: structured,
    );
    AppLogger.error(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_error ${failure.message}',
      failure.toTechnicalMessage(),
    );

    if (!completer.isCompleted) {
      _closeSocket();
    }

    // Fire-and-forget: ConnectionProvider._handleTokenExpired schedules its own
    // async recovery without blocking this synchronous socket event handler.
    if (_isAuthRelated(structured, errorMessage)) {
      _onTokenExpired?.call();
    }

    if (completer.isCompleted) {
      return;
    }

    completer.complete(Failure(failure));
  }

  void _handleSocketError(dynamic error) {
    final structured = _parseStructuredErrorPayload(error);
    final errorMessage = structured?.message ?? error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = _buildConnectionFailure(
      errorMessage,
      errorObj,
      structured: structured,
    );
    AppLogger.error(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=socket_error ${failure.message}',
      failure.toTechnicalMessage(),
    );

    if (_isAuthRelated(structured, errorMessage)) {
      _onTokenExpired?.call();
    }
  }

  /// Extracts structured fields when the hub sends a JSON-shaped error payload
  /// such as `{ "code": "auth_failed", "reason": "...", "message": "..." }` on
  /// `connect_error`. Returns null when the payload is plain text or unparsable.
  static _StructuredConnectError? _parseStructuredErrorPayload(dynamic error) {
    if (error is Map<String, dynamic>) {
      return _StructuredConnectError.fromMap(error);
    }
    if (error is Map) {
      return _StructuredConnectError.fromMap({
        for (final entry in error.entries) entry.key.toString(): entry.value,
      });
    }
    if (error is String) {
      final trimmed = error.trim();
      if (trimmed.isEmpty || (trimmed[0] != '{' && trimmed[0] != '[')) {
        return null;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return _StructuredConnectError.fromMap(decoded);
        }
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static bool _isAuthRelated(_StructuredConnectError? structured, String errorMessage) {
    if (structured != null && structured.isAuthRelated) {
      return true;
    }
    return _isAuthRelatedErrorMessage(errorMessage);
  }

  static bool _isAuthRelatedErrorMessage(String errorMessage) {
    return isHubConnectAuthRelatedMessage(errorMessage);
  }

  domain.Failure _buildConnectionFailure(
    String errorMessage,
    Object error, {
    _StructuredConnectError? structured,
    Map<String, Object>? extraContext,
  }) {
    final context = _connectFailureContext(
      structured: structured,
      extraContext: extraContext,
    );

    if (isHubConnectAuthRelatedMessage(errorMessage)) {
      return domain.ConfigurationFailure.withContext(
        message: 'Authentication failed. Please sign in again.',
        cause: error,
        context: context,
      );
    }

    return domain.NetworkFailure.withContext(
      message: 'Unable to connect to the hub. Check the server URL and your network connection.',
      cause: error,
      context: context,
    );
  }

  Map<String, Object> _connectFailureContext({
    _StructuredConnectError? structured,
    Map<String, Object>? extraContext,
  }) {
    final context = <String, Object>{
      'operation': 'connect',
      ...?extraContext,
    };
    final code = structured?.code;
    if (code != null && code.isNotEmpty) {
      context['hub_code'] = code;
    }
    final reason = structured?.reason;
    if (reason != null && reason.isNotEmpty) {
      context['hub_reason'] = reason;
    }
    final recoveryId = _resilienceRecoveryId;
    if (recoveryId != null && recoveryId.isNotEmpty) {
      context['recovery_id'] = recoveryId;
    }
    return context;
  }

  @override
  Future<Result<void>> disconnect() async {
    try {
      _connectGeneration++;
      _onHubLifecycle = null;
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
    unawaited(_rpcDispatcher.cancelActiveStreamOnDisconnect());
    final socket = _socket;
    _socket = null;
    _streamPullHandler.dispose();
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
      // Convert QueryResponse to RPC response format
      final result = {
        'execution_id': response.id,
        'started_at': response.timestamp.toIso8601String(),
        'finished_at': response.timestamp.toIso8601String(),
        'rows': response.data,
        'row_count': response.data.length,
        if (response.affectedRows != null) 'affected_rows': response.affectedRows,
        if (response.columnMetadata != null) 'column_metadata': response.columnMetadata,
        if (response.hasMultiResult) ...{
          'multi_result': true,
          'result_set_count': response.resultSets.length,
          'item_count': response.items.length,
          'result_sets': response.resultSets
              .map(
                (resultSet) => {
                  'index': resultSet.index,
                  'rows': resultSet.rows,
                  'row_count': resultSet.rowCount,
                  if (resultSet.affectedRows != null) 'affected_rows': resultSet.affectedRows,
                  if (resultSet.columnMetadata != null) 'column_metadata': resultSet.columnMetadata,
                },
              )
              .toList(growable: false),
          'items': response.items
              .map(
                (item) => item.resultSet != null
                    ? {
                        'type': 'result_set',
                        'index': item.index,
                        'result_set_index': item.resultSet!.index,
                        'rows': item.resultSet!.rows,
                        'row_count': item.resultSet!.rowCount,
                        if (item.resultSet!.affectedRows != null) 'affected_rows': item.resultSet!.affectedRows,
                        if (item.resultSet!.columnMetadata != null) 'column_metadata': item.resultSet!.columnMetadata,
                      }
                    : {
                        'type': 'row_count',
                        'index': item.index,
                        'affected_rows': item.rowCount,
                      },
              )
              .toList(growable: false),
        },
        if (response.pagination != null)
          'pagination': {
            'page': response.pagination!.page,
            'page_size': response.pagination!.pageSize,
            'returned_rows': response.pagination!.returnedRows,
            'has_next_page': response.pagination!.hasNextPage,
            'has_previous_page': response.pagination!.hasPreviousPage,
            if (response.pagination!.currentCursor != null) 'current_cursor': response.pagination!.currentCursor,
            if (response.pagination!.nextCursor != null) 'next_cursor': response.pagination!.nextCursor,
          },
      };

      final rpcResponse = response.error != null
          ? RpcResponse.error(
              id: response.requestId,
              error: RpcError(
                code: RpcErrorCode.sqlExecutionFailed,
                message: RpcErrorCode.getMessage(
                  RpcErrorCode.sqlExecutionFailed,
                ),
                data: RpcErrorCode.buildErrorData(
                  code: RpcErrorCode.sqlExecutionFailed,
                  technicalMessage: response.error!,
                  correlationId: response.requestId,
                ),
              ),
            )
          : RpcResponse.success(id: response.requestId, result: result);

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

  void _emitAgentHeartbeat() {
    final payload = <String, dynamic>{
      'agent_id': _agentId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'protocol': _currentProtocol.protocol,
    };
    _emitEvent('agent:heartbeat', payload);
  }

  void _emitAgentReady() {
    final payload = <String, dynamic>{
      'agent_id': _agentId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'protocol': _currentProtocol.protocol,
    };
    _emitEvent('agent:ready', payload);
  }

  void _logHeartbeatEvent(String direction, String event, dynamic data) {
    final enriched = data is Map<String, dynamic>
        ? <String, dynamic>{...data, 'agent_id': _agentId}
        : <String, dynamic>{'agent_id': _agentId, 'payload': data};
    _logMessage(direction, event, enriched);
  }

  void _handleHeartbeatAck(dynamic data) {
    dynamic payload = data;
    try {
      payload = _decodeIncomingPayloadOrThrow(
        data,
        sourceEvent: 'hub:heartbeat_ack',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Invalid hub:heartbeat_ack payload',
        error,
        stackTrace,
      );
      return;
    }
    _heartbeat.onAckReceived();
    _logMessage('RECEIVED', 'hub:heartbeat_ack', payload);
  }

  bool _supportsProtocolReadyAck() {
    final extensionValue = _currentProtocol.negotiatedExtensions['protocolReadyAck'];
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

  /// Extracts the JSON-RPC `id` from a single [RpcResponse] or the first
  /// element of a batch, returning null when the id cannot be resolved.
  static dynamic _extractResponseId(dynamic responseData) {
    if (responseData is RpcResponse) return responseData.id;
    if (responseData is List<RpcResponse> && responseData.isNotEmpty) {
      return responseData.first.id;
    }
    return null;
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

/// Structured `connect_error` payload emitted by hubs that follow the contract
/// `{ "code": "auth_failed", "reason": "...", "message": "..." }`. Falls back
/// to `code`/`reason` heuristics for plain Maps with non-standard fields.
class _StructuredConnectError {
  const _StructuredConnectError({this.code, this.reason, this.message});

  factory _StructuredConnectError.fromMap(Map<String, dynamic> map) {
    return _StructuredConnectError(
      code: map['code']?.toString(),
      reason: map['reason']?.toString(),
      message: map['message']?.toString() ?? map['detail']?.toString(),
    );
  }

  final String? code;
  final String? reason;
  final String? message;

  bool get isAuthRelated {
    if (isHubConnectAuthRelatedStructured(code: code, reason: reason)) {
      return true;
    }
    final msg = message;
    if (msg == null || msg.trim().isEmpty) {
      return false;
    }
    return isHubConnectAuthRelatedMessage(msg);
  }
}
