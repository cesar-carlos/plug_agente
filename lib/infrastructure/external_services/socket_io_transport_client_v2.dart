import 'dart:async';
import 'dart:convert';

import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/delivery_guarantee.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/stream_emitter_registry.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Socket.IO transport client for the v2 RPC contract.
class SocketIOTransportClientV2 implements ITransportClient {
  SocketIOTransportClientV2({
    required SocketDataSource dataSource,
    required ProtocolNegotiator negotiator,
    required RpcMethodDispatcher rpcDispatcher,
    required FeatureFlags featureFlags,
    PayloadSigner? payloadSigner,
    ProtocolMetricsCollector? protocolMetricsCollector,
    OpenRpcDocumentLoader? openRpcDocumentLoader,
    PayloadLogSummarizer? logSummarizer,
  }) : _dataSource = dataSource,
       _negotiator = negotiator,
       _rpcDispatcher = rpcDispatcher,
       _featureFlags = featureFlags,
       _payloadSigner = payloadSigner,
       _protocolMetricsCollector = protocolMetricsCollector,
       _openRpcDocumentLoader = openRpcDocumentLoader ?? OpenRpcDocumentLoader(),
       _logSummarizer = logSummarizer ?? PayloadLogSummarizer(
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
      localSignatureRequired: () => _localSignatureRequired,
      payloadSigner: _payloadSigner,
    );
    _responsePreparer = RpcResponsePreparer(
      featureFlags: _featureFlags,
      logSummarizer: _logSummarizer,
      contractValidator: _contractValidator,
      protocolProvider: () => _currentProtocol,
      usesBinaryTransport: () => _usesBinaryTransport,
      agentIdProvider: () => _agentId,
      payloadSigner: _payloadSigner,
    );
    _capabilitiesNegotiator = CapabilitiesNegotiator(
      negotiator: _negotiator,
      featureFlags: _featureFlags,
      contractValidator: _contractValidator,
      localCapabilitiesProvider: _localCapabilities,
      agentIdProvider: () => _agentId,
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
    _inboundHandler = RpcInboundHandler(
      featureFlags: _featureFlags,
      protocolProvider: () => _currentProtocol,
      agentIdProvider: () => _agentId,
      frameCodec: _frameCodec,
      logSummarizer: _logSummarizer,
      responsePreparer: _responsePreparer,
      authorizationDecisionLogger: _authorizationDecisionLogger,
      openRpcDocumentLoader: _openRpcDocumentLoader,
      dispatcher: _rpcDispatcher,
      requestGuard: _rpcRequestGuard,
      schemaValidator: _schemaValidator,
      streamEmitterFactory: _createStreamEmitter,
      emitRpcResponse: _emitRpcResponse,
      emitEvent: _emitEventAsync,
      hasReceivedCapabilities: () => _hasReceivedCapabilities,
    );
  }

  final SocketDataSource _dataSource;
  final ProtocolNegotiator _negotiator;
  final RpcMethodDispatcher _rpcDispatcher;
  final FeatureFlags _featureFlags;
  final PayloadSigner? _payloadSigner;
  final ProtocolMetricsCollector? _protocolMetricsCollector;
  final OpenRpcDocumentLoader _openRpcDocumentLoader;
  final PayloadLogSummarizer _logSummarizer;
  late final TransportPipelineCache _pipelineCache;
  late final PayloadFrameCodec _frameCodec;
  late final RpcResponsePreparer _responsePreparer;
  late final CapabilitiesNegotiator _capabilitiesNegotiator;
  late final AuthorizationDecisionLogger _authorizationDecisionLogger;
  late final RpcInboundHandler _inboundHandler;

  io.Socket? _socket;
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
  late final StreamEmitterRegistry _streamEmitters = StreamEmitterRegistry(
    hardCeiling: ConnectionConstants.maxConcurrentRpcStreams,
    idleTtl: ConnectionConstants.rpcStreamEmitterMaxIdle,
    capProvider: () => _currentProtocol.effectiveLimits.maxConcurrentStreams,
  );

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

  void _logMessage(String direction, String event, dynamic data) {
    final traced = _featureFlags.enableSocketSummarizeLargePayloadLogs && data != null
        ? _logSummarizer.summarize(direction, event, data)
        : data;
    _onMessage?.call(direction, event, traced);
  }

  ProtocolCapabilities _localCapabilities() {
    return ProtocolCapabilities.defaultCapabilities(
      binaryPayload: _featureFlags.enableBinaryPayload,
      compressions: _featureFlags.outboundCompressionMode == OutboundCompressionMode.none
          ? const ['none']
          : const ['gzip', 'none'],
      compressionThreshold: _featureFlags.compressionThreshold,
      signatureRequired: _localSignatureRequired,
      signatureAlgorithms: _localSignatureAlgorithms,
    );
  }

  bool get _localSignatureRequired => _featureFlags.enablePayloadSigning && _payloadSigner != null;

  List<String> get _localSignatureAlgorithms =>
      _payloadSigner == null ? const [] : const [PayloadSigner.supportedAlgorithm];

  bool get _hasReceivedCapabilities => _capabilitiesNegotiator.hasReceivedCapabilities;

  bool get _usesBinaryTransport {
    if (!_hasReceivedCapabilities) {
      return _featureFlags.enableBinaryPayload;
    }
    return _currentProtocol.usesBinaryPayload && _currentProtocol.usesTransportFrame;
  }

  IRpcStreamEmitter _createStreamEmitter() {
    if (!_featureFlags.enableSocketBackpressure) {
      return _SocketRpcStreamEmitter(_emitValidatedStreamEvent);
    }
    return BackpressureStreamEmitter(
      emit: _emitValidatedStreamEvent,
      onRegister: (streamId, emitter) {
        final accepted = _streamEmitters.tryRegister(streamId, emitter);
        if (!accepted) {
          AppLogger.warning(
            'rpc stream emitter rejected: cap (effective='
            '${_streamEmitters.effectiveCap}, hard_ceiling='
            '${ConnectionConstants.maxConcurrentRpcStreams}) reached. '
            'stream_id=$streamId',
          );
        }
      },
      onUnregister: _streamEmitters.unregister,
    );
  }

  void _handleStreamPull(dynamic data) {
    try {
      final payload = _decodeIncomingPayloadOrThrow(
        data,
        sourceEvent: 'rpc:stream.pull',
      );
      if (payload is! Map<String, dynamic>) {
        return;
      }
      final pull = RpcStreamPull.fromJson(payload);
      _logMessage('INFO', 'rpc:stream.pull', {
        'stream_id': pull.streamId,
        'window_size': pull.windowSize,
      });
      final emitter = _streamEmitters.get(pull.streamId);
      if (emitter != null) {
        _streamEmitters.touch(pull.streamId);
        emitter.releaseChunks(pull.windowSize);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to handle rpc:stream.pull',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _emitRpcResponse(dynamic responseData) async {
    final prepared = responseData is List<RpcResponse>
        ? responseData.map(_responsePreparer.prepareForSend).toList()
        : _responsePreparer.prepareForSend(responseData as RpcResponse);
    final validatedPayload = _responsePreparer.validateOutgoing(prepared);
    if (validatedPayload == null) {
      return;
    }
    final outgoingPayload = await _prepareOutgoingPayloadAsync(
      'rpc:response',
      validatedPayload,
    );
    if (outgoingPayload == null) {
      return;
    }

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
    try {
      _heartbeat.stop();

      _closeSocket();

      _agentId = agentId;
      _capabilitiesNegotiator.reset();
      _currentProtocol = const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
      );

      _socket = _dataSource.createSocket(serverUrl, authToken: authToken);

      final completer = Completer<Result<void>>();
      Timer? timeoutTimer;

      _socket!.on('connect', (_) async {
        timeoutTimer?.cancel();
        _logMessage('RECEIVED', 'connect', null);
        _authorizationDecisionLogger.resetSessionState();
        _heartbeat.resetTransientState();
        await _capabilitiesNegotiator.sendRegisterAndStartTimeout();

        if (!completer.isCompleted) {
          completer.complete(const Success<Object, Exception>(Object()));
        }
      });

      _socket!.on('reconnect', (_) async {
        _logMessage('RECEIVED', 'reconnect', null);
        _heartbeat.resetTransientState();
        await _capabilitiesNegotiator.sendReRegisterAfterReconnect();
      });

      _socket!.on('reconnect_attempt', (dynamic data) {
        _logMessage('RECEIVED', 'reconnect_attempt', data);
        final n = data is int ? data : (data is num ? data.toInt() : int.tryParse('$data'));
        _onHubLifecycle?.call(HubTransportReconnectAttempt(attemptNumber: n));
      });

      _socket!.on('reconnect_failed', (_) {
        _logMessage('ERROR', 'reconnect_failed', null);
        AppLogger.error('Reconnection failed after multiple attempts');
        _onReconnectionNeeded?.call();
      });

      _socket!.on('connect_error', (error) {
        timeoutTimer?.cancel();
        _logMessage('ERROR', 'connect_error', error);
        _handleConnectionError(error, completer);
      });

      _socket!.on('error', (error) {
        _logMessage('ERROR', 'socket_error', error);
        _handleSocketError(error);
      });

      _socket!.on('disconnect', (dynamic reason) {
        _logMessage('RECEIVED', 'disconnect', reason);
        _heartbeat.stop();
        unawaited(_rpcDispatcher.cancelActiveStreamOnDisconnect());
        final asString = reason is String ? reason : reason?.toString();
        _onHubLifecycle?.call(HubTransportDisconnected(reason: asString));
      });

      // Protocol negotiation response
      _socket!.on('agent:capabilities', (data) {
        _logMessage('RECEIVED', 'agent:capabilities', data);
        _handleCapabilitiesNegotiation(data);
      });

      // Hub-side rejection of agent:register (e.g. unsupported protocol).
      _socket!.on('agent:register_error', (data) {
        _logMessage('RECEIVED', 'agent:register_error', data);
        final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
        _capabilitiesNegotiator.handleRegisterError(map);
      });

      _socket!.on('hub:heartbeat_ack', _handleHeartbeatAck);

      _socket!.on('rpc:request', (data) {
        _logMessage('RECEIVED', 'rpc:request', data);
        if (!_inboundHandler.tryAcquireSlot()) {
          unawaited(_inboundHandler.emitConcurrencyLimitedError(data));
          return;
        }
        unawaited(_inboundHandler.handleRequestWithRelease(data));
      });

      if (_featureFlags.enableSocketBackpressure) {
        _socket!.on('rpc:stream.pull', (data) {
          _logMessage('RECEIVED', 'rpc:stream.pull', data);
          _handleStreamPull(data);
        });
      }

      _socket!.connect();

      timeoutTimer = Timer(
        const Duration(
          milliseconds: ConnectionConstants.socketConnectionTimeoutMs,
        ),
        () {
          if (!completer.isCompleted) {
            _socket?.dispose();
            _socket = null;
            completer.complete(
              Failure(
                domain.NetworkFailure.withContext(
                  message: 'Connection timeout',
                  context: {'timeout': true, 'timeout_stage': 'transport'},
                ),
              ),
            );
          }
        },
      );

      return await completer.future;
    } on Exception catch (e) {
      _socket?.dispose();
      _socket = null;
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to connect to server',
          cause: e,
          context: {'operation': 'connect'},
        ),
      );
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
          'limits: payload=${limits.maxPayloadBytes}B, '
          'rows=${limits.maxRows}, batch=${limits.maxBatchSize}',
        );

        if (_supportsProtocolReadyAck()) {
          _emitAgentReady();
        }

        _heartbeat.start();

        if (wasPostReconnect) {
          _onHubLifecycle?.call(const HubTransportAutoReconnectSucceeded());
        }
      case CapabilitiesNegotiationFailure(:final error, :final stackTrace):
        AppLogger.error(
          'Failed to negotiate mandatory transport contract',
          error,
          stackTrace,
        );
        _heartbeat.stop();
        _socket?.disconnect();
        _socket?.dispose();
        _socket = null;
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
    final outgoingPayload = await _prepareOutgoingPayloadAsync(
      event,
      logicalPayload,
    );
    if (outgoingPayload == null) {
      return;
    }
    _logMessage('SENT', event, logicalPayload);
    _socket!.emit(event, outgoingPayload);
  }

  Future<dynamic> _prepareOutgoingPayloadAsync(
    String event,
    dynamic logicalPayload,
  ) async {
    if (!_usesBinaryTransport) {
      AppLogger.error(
        'Attempted to emit $event without negotiated binary PayloadFrame transport',
      );
      return null;
    }
    return _frameCodec.prepareOutgoing(
      event: event,
      logicalPayload: logicalPayload,
    );
  }

  dynamic _decodeIncomingPayloadOrThrow(
    dynamic payload, {
    String? sourceEvent,
  }) {
    return _frameCodec.decodeIncoming(payload, sourceEvent: sourceEvent);
  }

  void _handleConnectionError(
    dynamic error,
    Completer<Result<void>> completer,
  ) {
    final structured = _parseStructuredErrorPayload(error);
    final errorMessage = structured?.message ?? error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = _buildConnectionFailure(errorMessage, errorObj);
    AppLogger.error('Connection error: ${failure.message}', failure.toTechnicalMessage());

    if (!completer.isCompleted) {
      _socket?.dispose();
      _socket = null;
    }

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
    final failure = _buildConnectionFailure(errorMessage, errorObj);
    AppLogger.error('Socket error: ${failure.message}', failure.toTechnicalMessage());

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
    return errorMessage.contains('Authentication') ||
        errorMessage.contains('Invalid token') ||
        errorMessage.contains('401');
  }

  domain.Failure _buildConnectionFailure(String errorMessage, Object error) {
    final normalizedError = errorMessage.toLowerCase();
    if (normalizedError.contains('authentication') ||
        normalizedError.contains('invalid token') ||
        normalizedError.contains('401')) {
      return domain.ConfigurationFailure.withContext(
        message: 'Authentication failed. Please sign in again.',
        cause: error,
        context: {'operation': 'connect'},
      );
    }

    return domain.NetworkFailure.withContext(
      message: 'Unable to connect to the hub. Check the server URL and your network connection.',
      cause: error,
      context: {'operation': 'connect'},
    );
  }

  @override
  Future<Result<void>> disconnect() async {
    try {
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
    _capabilitiesNegotiator.reset();
    _pipelineCache.reset();
    unawaited(_rpcDispatcher.cancelActiveStreamOnDisconnect());
    final socket = _socket;
    _socket = null;
    _streamEmitters.dispose();
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

  Future<void> _emitValidatedStreamEvent(
    String event,
    Map<String, dynamic> payload,
  ) async {
    if (_socket == null) {
      return;
    }

    if (_featureFlags.enableSocketSchemaValidation) {
      Result<void> validation;
      if (event == 'rpc:chunk') {
        validation = _contractValidator.validateStreamChunk(payload);
      } else if (event == 'rpc:complete') {
        validation = _contractValidator.validateStreamComplete(payload);
      } else {
        validation = const Success(unit);
      }
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()! as domain.Failure;
        AppLogger.error('Invalid $event payload: ${failure.message}');
        return;
      }
    }

    await _emitEventAsync(event, payload);
  }

  bool _supportsProtocolReadyAck() {
    final extensionValue = _currentProtocol.negotiatedExtensions['protocolReadyAck'];
    return extensionValue is bool && extensionValue;
  }
}

class _SocketRpcStreamEmitter implements IRpcStreamEmitter {
  _SocketRpcStreamEmitter(this._emitAsync);

  final Future<void> Function(String event, Map<String, dynamic> payload) _emitAsync;

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    await _emitAsync('rpc:chunk', chunk.toJson());
    return true;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {
    await _emitAsync('rpc:complete', complete.toJson());
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
    if (code != null) {
      final lc = code!.toLowerCase();
      if (lc.contains('auth') || lc == 'unauthorized' || lc == '401') return true;
    }
    if (reason != null) {
      final lr = reason!.toLowerCase();
      if (lr.contains('auth') || lr == 'token_revoked' || lr == 'unauthorized') return true;
    }
    return false;
  }
}
