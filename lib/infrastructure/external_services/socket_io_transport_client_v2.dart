import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/protocol_version.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/delivery_guarantee.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
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
  }) : _dataSource = dataSource,
       _negotiator = negotiator,
       _rpcDispatcher = rpcDispatcher,
       _featureFlags = featureFlags,
       _payloadSigner = payloadSigner,
       _protocolMetricsCollector = protocolMetricsCollector;

  final SocketDataSource _dataSource;
  final ProtocolNegotiator _negotiator;
  final RpcMethodDispatcher _rpcDispatcher;
  final FeatureFlags _featureFlags;
  final PayloadSigner? _payloadSigner;
  final ProtocolMetricsCollector? _protocolMetricsCollector;

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
  bool _isTokenRefreshRequested = false;
  late final SocketIoHeartbeatController _heartbeat = SocketIoHeartbeatController(
    isConnected: () => _socket?.connected ?? false,
    emitHeartbeat: _emitAgentHeartbeat,
    logMessage: _logHeartbeatEvent,
    onConnectionStale: () => _onReconnectionNeeded?.call(),
  );
  final RpcRequestGuard _rpcRequestGuard = RpcRequestGuard();
  final RpcRequestSchemaValidator _schemaValidator = const RpcRequestSchemaValidator();
  final RpcContractValidator _contractValidator = const RpcContractValidator();
  final Map<String, BackpressureStreamEmitter> _streamEmitters = {};
  TransportPipeline? _cachedSendPipeline;
  String _sendPipelineCacheKey = '';
  final Map<String, TransportPipeline> _receivePipelineByKey = {};
  Map<String, dynamic>? _cachedOpenRpcDocument;
  Future<Map<String, dynamic>>? _openRpcDocumentLoadFuture;
  bool _hasReceivedCapabilities = false;
  bool _awaitingPostReconnectCapabilities = false;
  Timer? _capabilitiesTimeoutTimer;
  int _capabilitiesReRegisterCount = 0;
  int _activeRpcHandlers = 0;

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
        ? _summarizeLargePayloadForTracing(direction, event, data)
        : data;
    _onMessage?.call(direction, event, traced);
  }

  dynamic _summarizeLargePayloadForTracing(
    String direction,
    String event,
    dynamic data,
  ) {
    const threshold = ConnectionConstants.socketLogPayloadSummaryThresholdBytes;
    try {
      final sink = _Utf8BudgetSink(threshold);
      final jsonSink = JsonUtf8Encoder().startChunkedConversion(sink);
      jsonSink.add(data);
      jsonSink.close();
      return data;
    } on _PayloadUtf8BudgetExceeded {
      return <String, Object?>{
        '_log': 'payload_summary',
        'direction': direction,
        'event': event,
        'truncated': true,
        'threshold_bytes': threshold,
        if (data is Map<String, dynamic>) ..._shallowRpcLogHints(data),
        if (data is List<dynamic>) 'list_length': data.length,
      };
    } on Object {
      return data;
    }
  }

  Map<String, Object?> _shallowRpcLogHints(Map<String, dynamic> map) {
    return <String, Object?>{
      if (map.containsKey('id')) 'id': map['id'],
      if (map.containsKey('method')) 'method': map['method'],
      if (map.containsKey('jsonrpc')) 'jsonrpc': map['jsonrpc'],
    };
  }

  bool _tryAcquireRpcHandlerSlot() {
    if (_activeRpcHandlers >= ConnectionConstants.maxConcurrentRpcHandlers) {
      return false;
    }
    _activeRpcHandlers++;
    return true;
  }

  void _releaseRpcHandlerSlot() {
    _activeRpcHandlers--;
  }

  Future<void> _handleRpcRequestWithRelease(dynamic data) async {
    try {
      await _handleRpcRequest(data);
    } finally {
      _releaseRpcHandlerSlot();
    }
  }

  Future<void> _emitRpcConcurrencyLimited(dynamic rawData) async {
    dynamic id;
    try {
      if (rawData is Map<String, dynamic> && _looksLikePayloadFrame(rawData)) {
        final payload = _decodeIncomingPayloadOrThrow(
          rawData,
          sourceEvent: 'rpc:request',
        );
        if (payload is Map<String, dynamic>) {
          id = payload['id'];
        }
      } else if (rawData is Map<String, dynamic>) {
        id = rawData['id'];
      }
    } on Object {
      id = null;
    }

    await _emitRpcResponse(
      _buildRpcErrorResponse(
        id: id,
        code: RpcErrorCode.rateLimited,
        technicalMessage:
            'Concurrent RPC handler limit exceeded '
            '(${ConnectionConstants.maxConcurrentRpcHandlers})',
      ),
    );
  }

  bool _utf8JsonExceedsByteBudget(dynamic payload, int budgetBytes) {
    if (budgetBytes <= 0) {
      return false;
    }
    try {
      final sink = _Utf8BudgetSink(budgetBytes);
      final jsonSink = JsonUtf8Encoder().startChunkedConversion(sink);
      jsonSink.add(payload);
      jsonSink.close();
      return false;
    } on _PayloadUtf8BudgetExceeded {
      return true;
    }
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

  bool get _usesBinaryTransport {
    if (!_hasReceivedCapabilities) {
      return _featureFlags.enableBinaryPayload;
    }
    return _currentProtocol.usesBinaryPayload && _currentProtocol.usesTransportFrame;
  }

  TransportPipeline _createSendPipeline() {
    final negotiatedCmp = _hasReceivedCapabilities ? _currentProtocol.compression : 'gzip';
    final String pipelineCompression;
    if (_featureFlags.outboundCompressionMode == OutboundCompressionMode.none || negotiatedCmp == 'none') {
      pipelineCompression = 'none';
    } else if (_featureFlags.outboundCompressionMode == OutboundCompressionMode.auto) {
      pipelineCompression = 'auto';
    } else {
      pipelineCompression = 'gzip';
    }
    final threshold = _hasReceivedCapabilities
        ? _currentProtocol.compressionThreshold
        : _featureFlags.compressionThreshold;
    final cacheKey = '${_currentProtocol.encoding}|$pipelineCompression|$threshold|$_hasReceivedCapabilities';
    if (_cachedSendPipeline != null && _sendPipelineCacheKey == cacheKey) {
      return _cachedSendPipeline!;
    }
    final pipeline = TransportPipeline(
      encoding: _currentProtocol.encoding,
      compression: pipelineCompression,
      compressionThreshold: threshold,
      protocol: _currentProtocol.protocol,
      metricsCollector: _protocolMetricsCollector,
    );
    _cachedSendPipeline = pipeline;
    _sendPipelineCacheKey = cacheKey;
    return pipeline;
  }

  TransportPipeline _createReceivePipeline(PayloadFrame frame) {
    final key =
        '${frame.enc}|${frame.cmp}|${frame.schemaVersion}|'
        '${_currentProtocol.compressionThreshold}';
    final cached = _receivePipelineByKey[key];
    if (cached != null) {
      return cached;
    }
    if (_receivePipelineByKey.length > 16) {
      _receivePipelineByKey.clear();
    }
    final pipeline = TransportPipeline(
      encoding: frame.enc,
      compression: frame.cmp,
      compressionThreshold: _currentProtocol.compressionThreshold,
      schemaVersion: frame.schemaVersion,
      protocol: _currentProtocol.protocol,
      metricsCollector: _protocolMetricsCollector,
    );
    _receivePipelineByKey[key] = pipeline;
    return pipeline;
  }

  IRpcStreamEmitter _createStreamEmitter() {
    if (_featureFlags.enableSocketBackpressure) {
      return BackpressureStreamEmitter(
        emit: _emitValidatedStreamEvent,
        onRegister: (streamId, emitter) {
          _streamEmitters[streamId] = emitter;
        },
        onUnregister: _streamEmitters.remove,
      );
    }
    return _SocketRpcStreamEmitter(_emitValidatedStreamEvent);
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
      _streamEmitters[pull.streamId]?.releaseChunks(pull.windowSize);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to handle rpc:stream.pull',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _emitRequestAck(dynamic requestId) async {
    if (requestId == null || _socket == null) return;
    final ackPayload = {
      'request_id': requestId.toString(),
      'received_at': DateTime.now().toIso8601String(),
    };
    await _emitEventAsync('rpc:request_ack', ackPayload);
  }

  Future<void> _emitBatchRequestAck(List<RpcRequest> requests) async {
    if (_socket == null || requests.isEmpty) return;
    final ids = requests.where((r) => r.id != null).map((r) => r.id.toString()).toList();
    if (ids.isEmpty) return;
    final ackPayload = {
      'request_ids': ids,
      'received_at': DateTime.now().toIso8601String(),
    };
    await _emitEventAsync('rpc:batch_ack', ackPayload);
  }

  Future<void> _emitRpcResponse(dynamic responseData) async {
    final prepared = responseData is List<RpcResponse>
        ? responseData.map(_prepareResponseForSend).toList()
        : _prepareResponseForSend(responseData as RpcResponse);
    final validatedPayload = _validateOutgoingRpcPayload(prepared);
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

    const maxRetries = DeliveryGuaranteeConfig.maxResponseRetries;
    final timeoutMs = DeliveryGuaranteeConfig.responseAckTimeout.inMilliseconds;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        _logMessage('SENT', 'rpc:response', validatedPayload);
        await _socket!.timeout(timeoutMs).emitWithAckAsync('rpc:response', outgoingPayload);
        return;
      } on Exception catch (e) {
        if (attempt < maxRetries) {
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
      _hasReceivedCapabilities = false;
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
        _isTokenRefreshRequested = false;
        _heartbeat.resetTransientState();
        _capabilitiesReRegisterCount = 0;
        await _sendAgentRegister();
        _startCapabilitiesTimeoutTimer();

        if (!completer.isCompleted) {
          completer.complete(const Success<Object, Exception>(Object()));
        }
      });

      _socket!.on('reconnect', (_) async {
        _logMessage('RECEIVED', 'reconnect', null);
        _heartbeat.resetTransientState();
        _capabilitiesReRegisterCount = 0;
        _awaitingPostReconnectCapabilities = true;
        await _sendAgentRegister();
        _startCapabilitiesTimeoutTimer();
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

      _socket!.on('hub:heartbeat_ack', _handleHeartbeatAck);

      _socket!.on('rpc:request', (data) {
        _logMessage('RECEIVED', 'rpc:request', data);
        if (!_tryAcquireRpcHandlerSlot()) {
          unawaited(_emitRpcConcurrencyLimited(data));
          return;
        }
        unawaited(_handleRpcRequestWithRelease(data));
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

  void _startCapabilitiesTimeoutTimer() {
    _capabilitiesTimeoutTimer?.cancel();
    _capabilitiesTimeoutTimer = Timer(
      const Duration(milliseconds: ConnectionConstants.capabilitiesTimeoutMs),
      () {
        if (_hasReceivedCapabilities || _socket == null) return;
        if (_capabilitiesReRegisterCount < ConnectionConstants.capabilitiesMaxReRegisterAttempts) {
          _capabilitiesReRegisterCount++;
          AppLogger.warning(
            'resilience: capabilities_timeout re_register_count=$_capabilitiesReRegisterCount '
            'max=${ConnectionConstants.capabilitiesMaxReRegisterAttempts}',
          );
          unawaited(_sendAgentRegister());
          _startCapabilitiesTimeoutTimer();
        } else {
          AppLogger.warning(
            'resilience: capabilities_timeout forcing_reconnect after_max_attempts',
          );
          _capabilitiesReRegisterCount = 0;
          _onReconnectionNeeded?.call();
        }
      },
    );
  }

  /// Sends agent registration with protocol capabilities.
  Future<void> _sendAgentRegister() async {
    final agentCapabilities = _localCapabilities();

    final registerData = {
      'agentId': _agentId,
      'timestamp': DateTime.now().toIso8601String(),
      'capabilities': agentCapabilities.toJson(),
    };

    if (_featureFlags.enableSocketSchemaValidation) {
      final validation = _contractValidator.validateAgentRegister(registerData);
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()! as domain.Failure;
        AppLogger.error('Invalid agent:register payload: ${failure.message}');
        return;
      }
    }

    await _emitEventAsync('agent:register', registerData);
  }

  /// Handles protocol capabilities negotiation.
  void _handleCapabilitiesNegotiation(dynamic data) {
    try {
      final payload = _decodeIncomingPayloadOrThrow(
        data,
        sourceEvent: 'agent:capabilities',
      );
      if (payload is! Map<String, dynamic>) {
        throw StateError('agent:capabilities payload must be an object');
      }
      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _contractValidator.validateAgentCapabilitiesEnvelope(
          payload,
        );
        if (validation.isError()) {
          final failure = validation.exceptionOrNull()! as domain.Failure;
          throw StateError(failure.message);
        }
      }

      final agentCapabilities = _localCapabilities();
      final serverCapabilities = payload['capabilities'] != null
          ? ProtocolCapabilities.fromJson(
              payload['capabilities'] as Map<String, dynamic>,
            )
          : agentCapabilities;

      _currentProtocol = _negotiator.negotiate(
        agentCapabilities: agentCapabilities,
        serverCapabilities: serverCapabilities,
      );
      _validateNegotiatedTransportContract(
        agentCapabilities: agentCapabilities,
        serverCapabilities: serverCapabilities,
      );
      _capabilitiesTimeoutTimer?.cancel();
      _capabilitiesTimeoutTimer = null;
      _hasReceivedCapabilities = true;
      _receivePipelineByKey.clear();

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

      if (_awaitingPostReconnectCapabilities) {
        _awaitingPostReconnectCapabilities = false;
        _onHubLifecycle?.call(const HubTransportAutoReconnectSucceeded());
      }
    } on Object catch (error, stackTrace) {
      _awaitingPostReconnectCapabilities = false;
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

  /// Handles RPC v2 request.
  Future<void> _handleRpcRequest(dynamic data) async {
    try {
      dynamic payload = data;
      void Function()? socketAck;

      if (data is List && data.length == 2 && data[1] is Function) {
        payload = data[0];
        socketAck = data[1] as void Function();
      }

      try {
        payload = await _decodeIncomingPayloadOrThrowAsync(
          payload,
          sourceEvent: 'rpc:request',
        );
      } on domain.Failure catch (failure) {
        final mapped = _mapInboundTransportDecodeFailure(failure);
        await _sendSchemaValidationError(
          _extractRequestIdFromWirePayload(payload),
          mapped.code,
          failure.message,
          errorReason: mapped.reason,
        );
        socketAck?.call();
        return;
      }

      if (payload is List) {
        await _handleRpcBatchRequest(payload);
        socketAck?.call();
        return;
      }

      if (payload is! Map<String, dynamic>) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidRequest,
          'Request must be a JSON object',
        );
        socketAck?.call();
        return;
      }

      final requestMap = payload;
      if (_exceedsPayloadLimit(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.invalidPayload,
          'Request exceeds negotiated payload limit',
        );
        socketAck?.call();
        return;
      }

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateSingle(
          requestMap,
          limits: _currentProtocol.effectiveLimits,
        );
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              requestMap['id'],
              _validationFailureCode(failure),
              failure.message,
            );
            socketAck?.call();
            return;
          }
        }
      }

      if (!_verifyIncomingSignature(requestMap)) {
        await _sendSchemaValidationError(
          requestMap['id'],
          RpcErrorCode.authenticationFailed,
          'Invalid payload signature',
          errorReason: RpcErrorCode.reasonInvalidSignature,
        );
        socketAck?.call();
        return;
      }

      final request = RpcRequest.fromJson(requestMap);
      if (_hasNullIdCompatibilityViolation(requestMap)) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidRequest,
          'id: null notifications require negotiated compatibility',
        );
        socketAck?.call();
        return;
      }

      if (_featureFlags.enableSocketDeliveryGuarantees && !request.isNotification) {
        await _emitRequestAck(request.id);
      }
      socketAck?.call();

      final guardResult = _rpcRequestGuard.evaluate(request);
      if (guardResult != RpcRequestGuardResult.allow) {
        final errorResponse = _buildRpcErrorResponse(
          id: request.id,
          code: _guardResultToCode(guardResult),
          technicalMessage: _guardResultToTechnicalMessage(guardResult),
        );
        await _emitRpcResponse(errorResponse);
        return;
      }

      if (request.method == 'rpc.discover') {
        if (!_featureFlags.enableSocketNotificationsContract || !request.isNotification) {
          final doc = await _getOpenRpcDocument();
          final response = _attachRequestTraceToResponse(
            request,
            RpcResponse.success(
              id: request.id,
              result: doc,
            ),
          );
          await _emitRpcResponse(response);
        }
        return;
      }
      final clientToken = _extractClientTokenFromRpcParams(request.params);
      final streamEmitter = !request.isNotification && _featureFlags.enableSocketStreamingChunks
          ? _createStreamEmitter()
          : null;
      final response = await _rpcDispatcher.dispatch(
        request,
        _agentId,
        clientToken: clientToken,
        streamEmitter: streamEmitter,
        limits: _currentProtocol.effectiveLimits,
        negotiatedExtensions: _currentProtocol.negotiatedExtensions,
      );
      final tracedResponse = _attachRequestTraceToResponse(request, response);
      _logAuthorizationDecision(
        request: request,
        response: tracedResponse,
        clientToken: clientToken,
      );

      if (_featureFlags.enableSocketNotificationsContract && request.isNotification) {
        return;
      }

      await _emitRpcResponse(tracedResponse);
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC request',
        error,
        stackTrace,
      );

      final errorResponse = RpcResponse.error(
        id: null,
        error: RpcError(
          code: RpcErrorCode.parseError,
          message: RpcErrorCode.getMessage(RpcErrorCode.parseError),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.parseError,
            technicalMessage: error.toString(),
            extra: {
              'error': error.toString(),
            },
          ),
        ),
      );

      await _emitRpcResponse(errorResponse);
    }
  }

  /// Handles RPC batch request.
  Future<void> _handleRpcBatchRequest(List<dynamic> data) async {
    try {
      if (data.isEmpty) {
        const code = RpcErrorCode.invalidRequest;
        final errorResponse = RpcResponse.error(
          id: null,
          error: RpcError(
            code: code,
            message: RpcErrorCode.getMessage(code),
            data: RpcErrorCode.buildErrorData(
              code: code,
              technicalMessage: 'Batch request cannot be empty',
              extra: {
                'detail': 'Batch request cannot be empty',
              },
            ),
          ),
        );
        await _emitRpcResponse(errorResponse);
        return;
      }

      if (_exceedsPayloadLimit(data)) {
        await _sendSchemaValidationError(
          null,
          RpcErrorCode.invalidPayload,
          'Batch request exceeds negotiated payload limit',
        );
        return;
      }

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateBatch(
          data,
          limits: _currentProtocol.effectiveLimits,
        );
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              null,
              _validationFailureCode(failure),
              failure.message,
            );
            return;
          }
        }
      }

      for (final item in data) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        if (!_verifyIncomingSignature(item)) {
          await _sendSchemaValidationError(
            item['id'],
            RpcErrorCode.authenticationFailed,
            'Invalid payload signature',
            errorReason: RpcErrorCode.reasonInvalidSignature,
          );
          return;
        }
      }

      final requests = data.map((e) => RpcRequest.fromJson(e as Map<String, dynamic>)).toList();

      for (final item in data.whereType<Map<String, dynamic>>()) {
        if (_hasNullIdCompatibilityViolation(item)) {
          await _sendSchemaValidationError(
            null,
            RpcErrorCode.invalidRequest,
            'id: null notifications require negotiated compatibility',
          );
          return;
        }
      }

      if (_featureFlags.enableSocketDeliveryGuarantees) {
        await _emitBatchRequestAck(requests);
      }

      if (_featureFlags.enableSocketBatchStrictValidation) {
        final batch = RpcBatchRequest(requests);
        final validation = batch.validateStrict(
          maxSize: _currentProtocol.effectiveLimits.maxBatchSize,
        );
        switch (validation) {
          case RpcBatchDuplicateIds(:final duplicateIds):
            final errorResponse = RpcResponse.error(
              id: null,
              error: RpcError(
                code: RpcErrorCode.invalidRequest,
                message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                data: RpcErrorCode.buildErrorData(
                  code: RpcErrorCode.invalidRequest,
                  technicalMessage: 'Batch contains duplicate request IDs: $duplicateIds',
                  reason: 'batch_duplicate_ids',
                  extra: {'duplicate_ids': duplicateIds},
                ),
              ),
            );
            await _emitRpcResponse(errorResponse);
            return;
          case RpcBatchExceedsLimit(:final size, :final limit):
            final errorResponse = RpcResponse.error(
              id: null,
              error: RpcError(
                code: RpcErrorCode.invalidRequest,
                message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                data: RpcErrorCode.buildErrorData(
                  code: RpcErrorCode.invalidRequest,
                  technicalMessage: 'Batch exceeds limit: $size > $limit',
                  reason: 'batch_exceeds_limit',
                  extra: {'size': size, 'limit': limit},
                ),
              ),
            );
            await _emitRpcResponse(errorResponse);
            return;
          case RpcBatchValid():
            break;
        }
      }

      final responses = <({int index, RpcResponse response})>[];

      for (var index = 0; index < requests.length; index++) {
        final request = requests[index];
        final guardResult = _rpcRequestGuard.evaluate(request);
        if (guardResult != RpcRequestGuardResult.allow) {
          final errorResponse = _buildRpcErrorResponse(
            id: request.id,
            code: _guardResultToCode(guardResult),
            technicalMessage: _guardResultToTechnicalMessage(guardResult),
          );
          if (!request.isNotification) {
            responses.add((index: index, response: errorResponse));
          }
          continue;
        }

        if (request.method == 'rpc.discover') {
          if (!_featureFlags.enableSocketNotificationsContract || !request.isNotification) {
            final doc = await _getOpenRpcDocument();
            responses.add((
              index: index,
              response: _attachRequestTraceToResponse(
                request,
                RpcResponse.success(
                  id: request.id,
                  result: doc,
                ),
              ),
            ));
          }
          continue;
        }

        final clientToken = _extractClientTokenFromRpcParams(request.params);
        final response = await _rpcDispatcher.dispatch(
          request,
          _agentId,
          clientToken: clientToken,
          limits: _currentProtocol.effectiveLimits,
          negotiatedExtensions: _currentProtocol.negotiatedExtensions,
        );
        final tracedResponse = _attachRequestTraceToResponse(request, response);
        _logAuthorizationDecision(
          request: request,
          response: tracedResponse,
          clientToken: clientToken,
        );
        if (_featureFlags.enableSocketNotificationsContract && request.isNotification) {
          continue;
        }
        responses.add((index: index, response: tracedResponse));
      }

      if (responses.isEmpty) {
        return;
      }

      final orderedResponses = _supportsOrderedBatchResponses()
          ? (responses.toList()..sort((left, right) => left.index.compareTo(right.index)))
                .map((entry) => entry.response)
                .toList()
          : responses.map((entry) => entry.response).toList();
      final batchResponse = orderedResponses;
      await _emitRpcResponse(batchResponse);
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC batch request',
        error,
        stackTrace,
      );
    }
  }

  int _validationFailureCode(domain.Failure failure) {
    final code = failure.context['rpc_error_code'];
    return code is int ? code : RpcErrorCode.invalidRequest;
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

    final prepareResult = await _createSendPipeline().prepareSendAsync(
      logicalPayload,
      traceId: _extractTraceId(logicalPayload),
      requestId: _extractRequestId(logicalPayload),
      metricEventName: event,
    );
    if (prepareResult.isError()) {
      final failure = prepareResult.exceptionOrNull();
      AppLogger.error(
        'Failed to frame $event payload for transport: $failure',
      );
      return null;
    }

    var frame = prepareResult.getOrThrow();
    if (frame.compressedSize > _currentProtocol.effectiveLimits.maxCompressedPayloadBytes) {
      AppLogger.error(
        '$event payload exceeds negotiated transport limit after framing',
      );
      return null;
    }
    if (frame.originalSize > _currentProtocol.effectiveLimits.maxDecodedPayloadBytes) {
      AppLogger.error(
        '$event payload exceeds negotiated decoded payload limit',
      );
      return null;
    }
    if (_shouldSignTransportFrames) {
      final signer = _payloadSigner;
      if (signer == null) {
        AppLogger.error(
          'Attempted to sign $event transport frame without configured signer',
        );
        return null;
      }
      frame = frame.copyWith(
        signature: signer.signFrame(frame).toJson(),
      );
    }
    return frame.toJson();
  }

  dynamic _decodeIncomingPayloadOrThrow(
    dynamic payload, {
    String? sourceEvent,
  }) {
    if (!_looksLikePayloadFrame(payload)) {
      throw domain.ValidationFailure.withContext(
        message: 'Application payload must be a PayloadFrame',
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }

    try {
      final frame = PayloadFrame.fromJson(payload as Map<String, dynamic>);
      final localCapabilities = _localCapabilities();
      if (!localCapabilities.supportsEncoding(frame.enc)) {
        throw domain.ValidationFailure.withContext(
          message: 'Unsupported payload encoding: ${frame.enc}',
          context: {'encoding': frame.enc},
        );
      }
      if (!localCapabilities.supportsCompression(frame.cmp)) {
        throw domain.ValidationFailure.withContext(
          message: 'Unsupported payload compression: ${frame.cmp}',
          context: {'compression': frame.cmp},
        );
      }
      if (!_verifyIncomingFrameSignature(frame)) {
        throw domain.ValidationFailure.withContext(
          message: 'Invalid transport frame signature',
          context: {
            'request_id': frame.requestId,
            'transport_signature_invalid': true,
          },
        );
      }

      final processed = _createReceivePipeline(frame).receiveProcess(
        frame,
        maxCompressedBytes: _currentProtocol.effectiveLimits.maxCompressedPayloadBytes,
        maxOriginalBytes: _currentProtocol.effectiveLimits.maxDecodedPayloadBytes,
        maxInflationRatio: _currentProtocol.maxInflationRatio,
        metricEventName: sourceEvent,
      );
      if (processed.isError()) {
        throw processed.exceptionOrNull()! as domain.Failure;
      }
      return processed.getOrThrow();
    } on domain.Failure {
      rethrow;
    } on Exception catch (error) {
      throw domain.ValidationFailure.withContext(
        message: 'Failed to decode transport frame',
        cause: error,
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }
  }

  Future<dynamic> _decodeIncomingPayloadOrThrowAsync(
    dynamic payload, {
    String? sourceEvent,
  }) async {
    if (!_looksLikePayloadFrame(payload)) {
      throw domain.ValidationFailure.withContext(
        message: 'Application payload must be a PayloadFrame',
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }

    try {
      final frame = PayloadFrame.fromJson(payload as Map<String, dynamic>);
      final localCapabilities = _localCapabilities();
      if (!localCapabilities.supportsEncoding(frame.enc)) {
        throw domain.ValidationFailure.withContext(
          message: 'Unsupported payload encoding: ${frame.enc}',
          context: {'encoding': frame.enc},
        );
      }
      if (!localCapabilities.supportsCompression(frame.cmp)) {
        throw domain.ValidationFailure.withContext(
          message: 'Unsupported payload compression: ${frame.cmp}',
          context: {'compression': frame.cmp},
        );
      }
      if (!_verifyIncomingFrameSignature(frame)) {
        throw domain.ValidationFailure.withContext(
          message: 'Invalid transport frame signature',
          context: {
            'request_id': frame.requestId,
            'transport_signature_invalid': true,
          },
        );
      }

      final processed = await _createReceivePipeline(frame).receiveProcessAsync(
        frame,
        maxCompressedBytes: _currentProtocol.effectiveLimits.maxCompressedPayloadBytes,
        maxOriginalBytes: _currentProtocol.effectiveLimits.maxDecodedPayloadBytes,
        maxInflationRatio: _currentProtocol.maxInflationRatio,
        metricEventName: sourceEvent,
      );
      if (processed.isError()) {
        throw processed.exceptionOrNull()! as domain.Failure;
      }
      return processed.getOrThrow();
    } on domain.Failure {
      rethrow;
    } on Exception catch (error) {
      throw domain.ValidationFailure.withContext(
        message: 'Failed to decode transport frame',
        cause: error,
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }
  }

  bool _looksLikePayloadFrame(dynamic payload) {
    return payload is Map<String, dynamic> &&
        payload.containsKey('schemaVersion') &&
        payload.containsKey('enc') &&
        payload.containsKey('cmp') &&
        payload.containsKey('payload') &&
        payload.containsKey('originalSize') &&
        payload.containsKey('compressedSize');
  }

  bool get _shouldSignTransportFrames =>
      _payloadSigner != null &&
      (_localSignatureRequired || (_hasReceivedCapabilities && _currentProtocol.signatureRequired));

  void _validateNegotiatedTransportContract({
    required ProtocolCapabilities agentCapabilities,
    required ProtocolCapabilities serverCapabilities,
  }) {
    if (!agentCapabilities.supportsBinaryPayload ||
        !serverCapabilities.supportsBinaryPayload ||
        !_currentProtocol.usesBinaryPayload ||
        !_currentProtocol.usesTransportFrame) {
      throw StateError(
        'Negotiated protocol does not satisfy mandatory binary PayloadFrame transport',
      );
    }

    final localCompressionThreshold = agentCapabilities.extensions['compressionThreshold'];
    if (localCompressionThreshold is! int || localCompressionThreshold < 1) {
      throw StateError('Local compressionThreshold capability is invalid');
    }
    if (_currentProtocol.compressionThreshold < 1) {
      throw StateError('Negotiated compressionThreshold is invalid');
    }
    if (_currentProtocol.maxInflationRatio < 1) {
      throw StateError('Negotiated maxInflationRatio is invalid');
    }

    final agentRequiresSignature = agentCapabilities.extensions['signatureRequired'] as bool? ?? false;
    final serverRequiresSignature = serverCapabilities.extensions['signatureRequired'] as bool? ?? false;
    if ((agentRequiresSignature || serverRequiresSignature) && _currentProtocol.signatureAlgorithms.isEmpty) {
      throw StateError(
        'Negotiated protocol requires signature but no shared algorithm was found',
      );
    }
    if (_currentProtocol.signatureRequired && _payloadSigner == null) {
      throw StateError(
        'Negotiated protocol requires transport signing but no signer is configured',
      );
    }
    if (_currentProtocol.signatureRequired &&
        !_currentProtocol.signatureAlgorithms.contains(
          PayloadSigner.supportedAlgorithm,
        )) {
      throw StateError(
        'Negotiated protocol requires unsupported signature algorithm',
      );
    }
  }

  bool _exceedsPayloadLimit(dynamic payload) {
    final limit = _currentProtocol.effectiveLimits.maxDecodedPayloadBytes;
    return _utf8JsonExceedsByteBudget(payload, limit);
  }

  dynamic _validateOutgoingRpcPayload(dynamic payload) {
    if (!_featureFlags.enableSocketSchemaValidation) {
      return payload;
    }
    if (!_featureFlags.enableSocketOutgoingContractValidation) {
      return payload;
    }

    const softCap = ConnectionConstants.socketOutgoingContractValidationMaxBytes;
    if (softCap > 0 && _utf8JsonExceedsByteBudget(payload, softCap)) {
      return payload;
    }

    final validation = payload is List<dynamic>
        ? _contractValidator.validateBatchResponse(payload)
        : _contractValidator.validateResponse(payload as Map<String, dynamic>);
    if (validation.isSuccess()) {
      return payload;
    }

    final failure = validation.exceptionOrNull()! as domain.Failure;
    AppLogger.error(
      'Outgoing rpc:response payload is invalid: ${failure.message}',
    );
    final fallback = _prepareResponseForSend(
      _buildRpcErrorResponse(
        id: null,
        code: RpcErrorCode.internalError,
        technicalMessage: 'Outgoing rpc:response failed contract validation',
      ),
    );

    final fallbackValidation = _contractValidator.validateResponse(fallback);
    if (fallbackValidation.isError()) {
      final fallbackFailure = fallbackValidation.exceptionOrNull()! as domain.Failure;
      AppLogger.error(
        'Fallback rpc:response payload is invalid: ${fallbackFailure.message}',
      );
      return null;
    }
    return fallback;
  }

  void _handleConnectionError(
    dynamic error,
    Completer<Result<void>> completer,
  ) {
    final errorMessage = error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = _buildConnectionFailure(errorMessage, errorObj);
    AppLogger.error('Connection error: ${failure.message}', error);

    if (!completer.isCompleted) {
      _socket?.dispose();
      _socket = null;
    }

    if (errorMessage.contains('Authentication') ||
        errorMessage.contains('Invalid token') ||
        errorMessage.contains('401')) {
      _onTokenExpired?.call();
    }

    if (completer.isCompleted) {
      return;
    }

    completer.complete(Failure(failure));
  }

  void _handleSocketError(dynamic error) {
    final errorMessage = error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = _buildConnectionFailure(errorMessage, errorObj);
    AppLogger.error('Socket error: ${failure.message}', error);

    if (errorMessage.contains('Authentication') ||
        errorMessage.contains('Invalid token') ||
        errorMessage.contains('401')) {
      _onTokenExpired?.call();
    }
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
      _isTokenRefreshRequested = false;
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
    _awaitingPostReconnectCapabilities = false;
    _capabilitiesTimeoutTimer?.cancel();
    _capabilitiesTimeoutTimer = null;
    _capabilitiesReRegisterCount = 0;
    _cachedSendPipeline = null;
    _sendPipelineCacheKey = '';
    _receivePipelineByKey.clear();
    unawaited(_rpcDispatcher.cancelActiveStreamOnDisconnect());
    final socket = _socket;
    _socket = null;
    _streamEmitters.clear();
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

  void _logAuthorizationDecision({
    required RpcRequest request,
    required RpcResponse response,
    required String? clientToken,
  }) {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return;
    }

    if (clientToken == null || clientToken.isEmpty) {
      return;
    }

    final isAuthRelevantMethod =
        request.method.startsWith('sql.') ||
        (request.method == 'client_token.getPolicy' && _featureFlags.enableClientTokenPolicyIntrospection);
    if (!isAuthRelevantMethod) {
      return;
    }

    final error = response.error;
    if (error == null) {
      _logMessage('AUTH', 'authorization.allowed', {
        'request_id': request.id,
        'method': request.method,
      });
      return;
    }

    final errorData = error.data;
    final reason = errorData is Map<String, dynamic> ? (errorData['reason'] as String?) : null;

    if (error.code == RpcErrorCode.authenticationFailed) {
      _logMessage('AUTH', 'authorization.authentication_failed', {
        'request_id': request.id,
        'method': request.method,
        ...?reason != null ? {'reason': reason} : null,
      });
      _requestTokenRefresh('authentication_failed');
      return;
    }

    if (error.code != RpcErrorCode.unauthorized) {
      return;
    }

    final payload = <String, dynamic>{
      'request_id': request.id,
      'method': request.method,
      'code': error.code,
      'reason': 'unauthorized',
    };

    if (errorData is Map<String, dynamic>) {
      payload.addAll({
        'reason': errorData['reason'] ?? payload['reason'],
        'client_id': errorData['client_id'],
        'operation': errorData['operation'],
        'resource': errorData['resource'],
      });
      payload.removeWhere((key, value) => value == null);
    }

    _logMessage('AUTH', 'authorization.denied', payload);

    if (payload['reason'] == 'token_revoked') {
      _requestTokenRefresh('token_revoked');
    }
  }

  void _requestTokenRefresh(String reason) {
    if (_isTokenRefreshRequested) {
      return;
    }

    _isTokenRefreshRequested = true;
    _logMessage('AUTH', 'authorization.token_refresh_requested', {
      'reason': reason,
      'agent_id': _agentId,
    });
    _onTokenExpired?.call();
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

  int _guardResultToCode(RpcRequestGuardResult result) {
    switch (result) {
      case RpcRequestGuardResult.allow:
        return RpcErrorCode.internalError;
      case RpcRequestGuardResult.rateLimited:
        return RpcErrorCode.rateLimited;
      case RpcRequestGuardResult.replayDetected:
        return RpcErrorCode.replayDetected;
    }
  }

  String _guardResultToTechnicalMessage(RpcRequestGuardResult result) {
    switch (result) {
      case RpcRequestGuardResult.allow:
        return 'Unexpected guard result';
      case RpcRequestGuardResult.rateLimited:
        return 'Rate limit exceeded for rpc:request';
      case RpcRequestGuardResult.replayDetected:
        return 'Duplicate request id within replay window';
    }
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

  bool _hasNullIdCompatibilityViolation(Map<String, dynamic> requestMap) {
    return requestMap.containsKey('id') && requestMap['id'] == null && !_allowsNullIdNotifications();
  }

  bool _allowsNullIdNotifications() {
    final extensionValue = _currentProtocol.negotiatedExtensions['notificationNullIdCompatibility'];
    if (extensionValue is bool) {
      return extensionValue;
    }
    return true;
  }

  bool _supportsOrderedBatchResponses() {
    final extensionValue = _currentProtocol.negotiatedExtensions['orderedBatchResponses'];
    if (extensionValue is bool) {
      return extensionValue;
    }
    return true;
  }

  bool _supportsProtocolReadyAck() {
    final extensionValue = _currentProtocol.negotiatedExtensions['protocolReadyAck'];
    return extensionValue is bool && extensionValue;
  }

  Map<String, dynamic> _prepareResponseForSend(RpcResponse response) {
    late final Map<String, dynamic> json;
    if (_featureFlags.enableSocketApiVersionMeta) {
      final existingMeta = Map<String, dynamic>.from(
        response.meta?.toJson() ?? const <String, dynamic>{},
      );
      json = <String, dynamic>{
        'jsonrpc': response.jsonrpc,
        'id': response.id,
        if (response.result != null) 'result': response.result,
        if (response.error != null) 'error': response.error!.toJson(),
        'api_version': ProtocolVersion.apiVersion,
        'meta': <String, dynamic>{
          ...existingMeta,
          'agent_id': _agentId,
          'request_id': response.id?.toString(),
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };
    } else {
      json = <String, dynamic>{
        'jsonrpc': response.jsonrpc,
        'id': response.id,
        if (response.result != null) 'result': response.result,
        if (response.error != null) 'error': response.error!.toJson(),
        if (response.apiVersion != null) 'api_version': response.apiVersion,
        if (response.meta != null) 'meta': response.meta!.toJson(),
      };
    }
    if (!_usesBinaryTransport && _featureFlags.enablePayloadSigning) {
      final signer = _payloadSigner;
      if (signer != null) {
        json['signature'] = signer.sign(json).toJson();
      }
    }
    return json;
  }

  RpcResponse _attachRequestTraceToResponse(
    RpcRequest request,
    RpcResponse response,
  ) {
    final requestMeta = request.meta;
    final responseMeta = response.meta;
    final supportedTraceContext = _currentProtocol.negotiatedExtensions['traceContext'];
    final traceModes = supportedTraceContext is List<dynamic>
        ? supportedTraceContext.whereType<String>().toSet()
        : {'w3c-trace-context', 'legacy-trace-id'};
    final mergedMeta = RpcProtocolMeta(
      traceId: traceModes.contains('legacy-trace-id') ? responseMeta?.traceId ?? requestMeta?.traceId : null,
      traceParent: traceModes.contains('w3c-trace-context')
          ? responseMeta?.traceParent ?? requestMeta?.traceParent
          : null,
      traceState: traceModes.contains('w3c-trace-context') ? responseMeta?.traceState ?? requestMeta?.traceState : null,
      requestId: responseMeta?.requestId ?? requestMeta?.requestId,
      agentId: responseMeta?.agentId,
      timestamp: responseMeta?.timestamp,
    );

    if (response.isError) {
      return RpcResponse.error(
        id: response.id,
        error: response.error!,
        apiVersion: response.apiVersion,
        meta: mergedMeta,
      );
    }

    return RpcResponse.success(
      id: response.id,
      result: response.result,
      apiVersion: response.apiVersion,
      meta: mergedMeta,
    );
  }

  bool _verifyIncomingSignature(Map<String, dynamic> payload) {
    if (!_featureFlags.enablePayloadSigning || _payloadSigner == null) {
      return true;
    }
    final sigJson = payload['signature'] as Map<String, dynamic>?;
    if (sigJson == null) return true;
    final signature = PayloadSignature.fromJson(sigJson);
    return _payloadSigner.verify(payload, signature);
  }

  bool _verifyIncomingFrameSignature(PayloadFrame frame) {
    final signatureRequired = _hasReceivedCapabilities ? _currentProtocol.signatureRequired : _localSignatureRequired;
    if (_payloadSigner == null) {
      return !signatureRequired;
    }
    final sigJson = frame.signature;
    if (sigJson == null) {
      return !signatureRequired;
    }
    final signature = PayloadSignature.fromJson(sigJson);
    return _payloadSigner.verifyFrame(frame, signature);
  }

  String? _extractTraceId(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final meta = payload['meta'];
    if (meta is! Map<String, dynamic>) {
      return payload['trace_id'] as String?;
    }
    return meta['trace_id'] as String?;
  }

  String? _extractRequestId(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final requestId = payload['id'] ?? payload['request_id'];
    if (requestId != null) {
      return requestId.toString();
    }
    final meta = payload['meta'];
    if (meta is Map<String, dynamic>) {
      final metaRequestId = meta['request_id'];
      if (metaRequestId != null) {
        return metaRequestId.toString();
      }
    }
    return null;
  }

  dynamic _extractRequestIdFromWirePayload(dynamic payload) {
    if (_looksLikePayloadFrame(payload)) {
      return (payload as Map<String, dynamic>)['requestId'];
    }
    if (payload is Map<String, dynamic>) {
      return payload['id'] ?? payload['request_id'];
    }
    return null;
  }

  Future<void> _sendSchemaValidationError(
    dynamic id,
    int code,
    String technicalMessage, {
    String? errorReason,
  }) async {
    final errorResponse = _buildRpcErrorResponse(
      id: id,
      code: code,
      technicalMessage: technicalMessage,
      errorReason: errorReason,
    );
    await _emitRpcResponse(errorResponse);
  }

  ({int code, String? reason}) _mapInboundTransportDecodeFailure(
    domain.Failure failure,
  ) {
    if (failure is domain.ValidationFailure && failure.context['transport_signature_invalid'] == true) {
      return (
        code: RpcErrorCode.authenticationFailed,
        reason: RpcErrorCode.reasonInvalidSignature,
      );
    }
    return (code: RpcErrorCode.invalidPayload, reason: null);
  }

  RpcResponse _buildRpcErrorResponse({
    required dynamic id,
    required int code,
    required String technicalMessage,
    String? errorReason,
  }) {
    return RpcResponse.error(
      id: id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: technicalMessage,
          reason: errorReason,
        ),
      ),
    );
  }

  String? _extractClientTokenFromRpcParams(dynamic params) {
    if (params is! Map<String, dynamic>) return null;
    final raw = params['client_token'] as String? ?? params['auth'] as String? ?? params['clientToken'] as String?;
    return raw != null && raw.trim().isNotEmpty ? raw.trim() : null;
  }

  Future<Map<String, dynamic>> _getOpenRpcDocument() async {
    final cached = _cachedOpenRpcDocument;
    if (cached != null) {
      return cached;
    }

    _openRpcDocumentLoadFuture ??= _loadOpenRpcDocumentAsync();
    return _openRpcDocumentLoadFuture!;
  }

  Future<Map<String, dynamic>> _loadOpenRpcDocumentAsync() async {
    try {
      final content = await rootBundle.loadString(
        'docs/communication/openrpc.json',
      );
      final json = jsonDecode(content) as Map<String, dynamic>;
      _cachedOpenRpcDocument = json;
      return json;
    } on Object catch (assetError, assetStack) {
      try {
        final filePath = path.join(
          Directory.current.path,
          'docs',
          'communication',
          'openrpc.json',
        );
        final content = await File(filePath).readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _cachedOpenRpcDocument = json;
        return json;
      } on Object catch (fileError, _) {
        AppLogger.warning(
          'Failed to load OpenRPC from asset and disk, using fallback',
          assetError,
          assetStack,
        );
      }
    }

    const fallback = <String, dynamic>{
      'openrpc': '1.3.2',
      'info': <String, dynamic>{
        'title': 'Plug Agente Socket RPC',
        'version': ProtocolVersion.openRpcVersion,
      },
      'methods': <dynamic>[],
    };
    _cachedOpenRpcDocument = fallback;
    return fallback;
  }
}

class _PayloadUtf8BudgetExceeded implements Exception {
  const _PayloadUtf8BudgetExceeded();
}

class _Utf8BudgetSink extends ByteConversionSinkBase {
  _Utf8BudgetSink(this.budgetBytes);

  final int budgetBytes;
  int _total = 0;

  @override
  void add(List<int> chunk) {
    _total += chunk.length;
    if (_total > budgetBytes) {
      throw const _PayloadUtf8BudgetExceeded();
    }
  }

  @override
  void close() {}
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
