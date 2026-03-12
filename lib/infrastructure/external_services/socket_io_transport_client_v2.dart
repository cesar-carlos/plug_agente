import 'dart:async';

import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/delivery_guarantee.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/models/envelope_model.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Socket.IO transport client with dual protocol support (v1 legacy + v2 RPC).
///
/// Supports protocol negotiation, compression, and automatic fallback to legacy.
class SocketIOTransportClientV2 implements ITransportClient {
  SocketIOTransportClientV2({
    required SocketDataSource dataSource,
    required ProtocolNegotiator negotiator,
    required RpcMethodDispatcher rpcDispatcher,
    required FeatureFlags featureFlags,
  }) : _dataSource = dataSource,
       _negotiator = negotiator,
       _rpcDispatcher = rpcDispatcher,
       _featureFlags = featureFlags;

  final SocketDataSource _dataSource;
  final ProtocolNegotiator _negotiator;
  final RpcMethodDispatcher _rpcDispatcher;
  final FeatureFlags _featureFlags;

  io.Socket? _socket;
  String _agentId = '';
  ProtocolConfig _currentProtocol = const ProtocolConfig(
    protocol: 'legacy-envelope-v1',
    encoding: 'json',
    compression: 'none',
  );

  final StreamController<QueryRequest> _queryRequestController =
      StreamController<QueryRequest>.broadcast();

  void Function(String direction, String event, dynamic data)? _onMessage;
  void Function()? _onTokenExpired;
  void Function()? _onReconnectionNeeded;
  bool _isTokenRefreshRequested = false;
  Timer? _heartbeatTimer;
  Timer? _heartbeatAckTimer;
  bool _isWaitingHeartbeatAck = false;
  int _missedHeartbeats = 0;

  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const Duration _heartbeatAckTimeout = Duration(seconds: 8);
  static const int _maxMissedHeartbeats = 2;
  final RpcRequestGuard _rpcRequestGuard = RpcRequestGuard();
  final RpcRequestSchemaValidator _schemaValidator =
      const RpcRequestSchemaValidator();
  final Map<String, BackpressureStreamEmitter> _streamEmitters = {};

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

  void _logMessage(String direction, String event, dynamic data) {
    _onMessage?.call(direction, event, data);
  }

  IRpcStreamEmitter _createStreamEmitter() {
    if (_featureFlags.enableSocketBackpressure) {
      return BackpressureStreamEmitter(
        emit: (event, payload) {
          _logMessage('SENT', event, payload);
          _socket?.emit(event, payload);
        },
        onRegister: (streamId, emitter) {
          _streamEmitters[streamId] = emitter;
        },
        onUnregister: _streamEmitters.remove,
      );
    }
    return _SocketRpcStreamEmitter(_socket, _logMessage);
  }

  void _handleStreamPull(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    try {
      final pull = RpcStreamPull.fromJson(data);
      _logMessage('INFO', 'rpc:stream.pull', {
        'stream_id': pull.streamId,
        'window_size': pull.windowSize,
      });
      _streamEmitters[pull.streamId]?.releaseChunks(pull.windowSize);
    } on Object catch (_) {}
  }

  void _emitRequestAck(dynamic requestId) {
    if (requestId == null || _socket == null) return;
    final ackPayload = {
      'request_id': requestId.toString(),
      'received_at': DateTime.now().toIso8601String(),
    };
    _logMessage('SENT', 'rpc:request_ack', ackPayload);
    _socket!.emit('rpc:request_ack', ackPayload);
  }

  void _emitBatchRequestAck(List<RpcRequest> requests) {
    if (_socket == null || requests.isEmpty) return;
    final ids = requests
        .where((r) => r.id != null)
        .map((r) => r.id.toString())
        .toList();
    if (ids.isEmpty) return;
    final ackPayload = {
      'request_ids': ids,
      'received_at': DateTime.now().toIso8601String(),
    };
    _logMessage('SENT', 'rpc:batch_ack', ackPayload);
    _socket!.emit('rpc:batch_ack', ackPayload);
  }

  Future<void> _emitRpcResponse(dynamic responseData) async {
    final prepared = responseData is List<RpcResponse>
        ? responseData.map(_prepareResponseForSend).toList()
        : _prepareResponseForSend(responseData as RpcResponse);

    if (!_featureFlags.enableSocketDeliveryGuarantees || _socket == null) {
      _logMessage('SENT', 'rpc:response', prepared);
      _socket?.emit('rpc:response', prepared);
      return;
    }

    const maxRetries = DeliveryGuaranteeConfig.maxResponseRetries;
    final timeoutMs = DeliveryGuaranteeConfig.responseAckTimeout.inMilliseconds;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        _logMessage('SENT', 'rpc:response', prepared);
        await _socket!
            .timeout(timeoutMs)
            .emitWithAckAsync('rpc:response', prepared);
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
          _socket?.emit('rpc:response', prepared);
        }
      }
    }
  }

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  String get agentId => _agentId;

  @override
  Stream<QueryRequest> get queryRequestStream => _queryRequestController.stream;

  @override
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  }) async {
    try {
      _stopHeartbeat();

      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
        _socket = null;
      }

      _agentId = agentId;

      _socket = _dataSource.createSocket(serverUrl, authToken: authToken);

      final completer = Completer<Result<void>>();
      Timer? timeoutTimer;

      _socket!.on('connect', (_) {
        timeoutTimer?.cancel();
        _logMessage('RECEIVED', 'connect', null);
        _isTokenRefreshRequested = false;
        _missedHeartbeats = 0;
        _isWaitingHeartbeatAck = false;
        _sendAgentRegister();

        if (!completer.isCompleted) {
          completer.complete(const Success<Object, Exception>(Object()));
        }
      });

      _socket!.on('reconnect', (_) {
        _logMessage('RECEIVED', 'reconnect', null);
        _missedHeartbeats = 0;
        _isWaitingHeartbeatAck = false;
        _sendAgentRegister();
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

      _socket!.on('disconnect', (reason) {
        _logMessage('RECEIVED', 'disconnect', reason);
        _stopHeartbeat();
        _socket = null;
      });

      // Protocol negotiation response
      _socket!.on('agent:capabilities', (data) {
        _logMessage('RECEIVED', 'agent:capabilities', data);
        _handleCapabilitiesNegotiation(data as Map<String, dynamic>);
      });

      _socket!.on('hub:heartbeat_ack', _handleHeartbeatAck);

      // Legacy protocol events
      _socket!.on('query:request', (data) {
        _logMessage('RECEIVED', 'query:request', data);
        _handleLegacyQueryRequest(data as Map<String, dynamic>);
      });

      // RPC v2 protocol events
      _socket!.on('rpc:request', (data) {
        _logMessage('RECEIVED', 'rpc:request', data);
        _handleRpcRequest(data);
      });

      if (_featureFlags.enableSocketBackpressure) {
        _socket!.on('rpc:stream.pull', (data) {
          _logMessage('RECEIVED', 'rpc:stream.pull', data);
          _handleStreamPull(data);
        });
      }

      _socket!.connect();

      timeoutTimer = Timer(const Duration(seconds: 10), () {
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
      });

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

  /// Sends agent registration with protocol capabilities.
  void _sendAgentRegister() {
    final agentCapabilities = _featureFlags.enableJsonRpcV2
        ? ProtocolCapabilities.defaultCapabilities()
        : ProtocolCapabilities.legacyOnly();

    final registerData = {
      'agentId': _agentId,
      'timestamp': DateTime.now().toIso8601String(),
      'capabilities': agentCapabilities.toJson(),
    };

    _logMessage('SENT', 'agent:register', registerData);
    _socket!.emit('agent:register', registerData);
  }

  /// Handles protocol capabilities negotiation.
  void _handleCapabilitiesNegotiation(Map<String, dynamic> data) {
    try {
      final serverCapabilities = data['capabilities'] != null
          ? ProtocolCapabilities.fromJson(
              data['capabilities'] as Map<String, dynamic>,
            )
          : ProtocolCapabilities.legacyOnly();

      final agentCapabilities = _featureFlags.enableJsonRpcV2
          ? ProtocolCapabilities.defaultCapabilities()
          : ProtocolCapabilities.legacyOnly();

      _currentProtocol = _negotiator.negotiate(
        agentCapabilities: agentCapabilities,
        serverCapabilities: serverCapabilities,
        preferJsonRpcV2: _featureFlags.enableJsonRpcV2,
      );

      AppLogger.info(
        'Protocol negotiated: ${_currentProtocol.protocol}, '
        'encoding: ${_currentProtocol.encoding}, '
        'compression: ${_currentProtocol.compression}',
      );

      if (_currentProtocol.isJsonRpcV2) {
        _startHeartbeat();
      } else {
        _stopHeartbeat();
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to negotiate protocol, falling back to legacy',
        error,
        stackTrace,
      );
      _fallbackToLegacy();
    }
  }

  /// Handles legacy query:request event.
  void _handleLegacyQueryRequest(Map<String, dynamic> data) {
    try {
      final envelope = EnvelopeModel.fromJson(data);
      final request = _envelopeToQueryRequest(envelope);
      _queryRequestController.add(request);
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing legacy query request',
        error,
        stackTrace,
      );
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

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateSingle(requestMap);
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              requestMap['id'],
              RpcErrorCode.invalidRequest,
              failure.message,
            );
            return;
          }
        }
      }

      // Single request
      final request = RpcRequest.fromJson(requestMap);

      if (_featureFlags.enableSocketDeliveryGuarantees) {
        _emitRequestAck(request.id);
      }
      socketAck?.call();

      if (_featureFlags.enableSocketNotificationsContract &&
          request.isNotification) {
        return;
      }

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
      final clientToken = _extractClientTokenFromRpcParams(request.params);
      final streamEmitter = _featureFlags.enableSocketStreamingChunks
          ? _createStreamEmitter()
          : null;
      final response = await _rpcDispatcher.dispatch(
        request,
        _agentId,
        clientToken: clientToken,
        streamEmitter: streamEmitter,
      );
      _logAuthorizationDecision(
        request: request,
        response: response,
        clientToken: clientToken,
      );

      await _emitRpcResponse(response);
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

      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _schemaValidator.validateBatch(data);
        if (validation.isError()) {
          final failure = validation.exceptionOrNull() as domain.Failure?;
          if (failure != null) {
            await _sendSchemaValidationError(
              null,
              RpcErrorCode.invalidRequest,
              failure.message,
            );
            return;
          }
        }
      }

      final requests = data
          .map((e) => RpcRequest.fromJson(e as Map<String, dynamic>))
          .toList();

      if (_featureFlags.enableSocketDeliveryGuarantees) {
        _emitBatchRequestAck(requests);
      }

      if (_featureFlags.enableSocketBatchStrictValidation) {
        final batch = RpcBatchRequest(requests);
        final validation = batch.validateStrict();
        switch (validation) {
          case RpcBatchDuplicateIds(:final duplicateIds):
            final errorResponse = RpcResponse.error(
              id: null,
              error: RpcError(
                code: RpcErrorCode.invalidRequest,
                message: RpcErrorCode.getMessage(RpcErrorCode.invalidRequest),
                data: RpcErrorCode.buildErrorData(
                  code: RpcErrorCode.invalidRequest,
                  technicalMessage:
                      'Batch contains duplicate request IDs: $duplicateIds',
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

      final responses = <RpcResponse>[];

      for (final request in requests) {
        if (_featureFlags.enableSocketNotificationsContract &&
            request.isNotification) {
          continue;
        }

        final guardResult = _rpcRequestGuard.evaluate(request);
        if (guardResult != RpcRequestGuardResult.allow) {
          responses.add(
            _buildRpcErrorResponse(
              id: request.id,
              code: _guardResultToCode(guardResult),
              technicalMessage: _guardResultToTechnicalMessage(guardResult),
            ),
          );
          continue;
        }

        final clientToken = _extractClientTokenFromRpcParams(request.params);
        final response = await _rpcDispatcher.dispatch(
          request,
          _agentId,
          clientToken: clientToken,
        );
        _logAuthorizationDecision(
          request: request,
          response: response,
          clientToken: clientToken,
        );
        responses.add(response);
      }

      // Send batch response
      final batchResponse = responses;
      await _emitRpcResponse(batchResponse);
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC batch request',
        error,
        stackTrace,
      );
    }
  }

  void _handleConnectionError(
    dynamic error,
    Completer<Result<void>> completer,
  ) {
    final errorMessage = error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = _buildConnectionFailure(errorMessage, errorObj);
    AppLogger.error('Connection error: ${failure.message}', error);

    _socket?.dispose();
    _socket = null;

    if (errorMessage.contains('Authentication') ||
        errorMessage.contains('Invalid token') ||
        errorMessage.contains('401')) {
      _onTokenExpired?.call();
    }

    if (!completer.isCompleted) {
      completer.complete(Failure(failure));
    }
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
      message:
          'Unable to connect to the hub. Check the server URL and your network connection.',
      cause: error,
      context: {'operation': 'connect'},
    );
  }

  /// Fallback to legacy protocol.
  void _fallbackToLegacy() {
    _currentProtocol = const ProtocolConfig(
      protocol: 'legacy-envelope-v1',
      encoding: 'json',
      compression: 'none',
    );
    _stopHeartbeat();

    AppLogger.info('Fell back to legacy protocol');
  }

  @override
  Future<Result<void>> disconnect() async {
    try {
      _stopHeartbeat();
      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
        _socket = null;
      }
      _isTokenRefreshRequested = false;
      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to disconnect',
          cause: e,
          context: {'operation': 'disconnect'},
        ),
      );
    }
  }

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async {
    try {
      if (_socket == null || !_socket!.connected) {
        return Failure(domain.NetworkFailure('Not connected to server'));
      }

      // Use protocol-aware sending
      if (_currentProtocol.isJsonRpcV2) {
        return await _sendRpcResponse(response);
      } else {
        return await _sendLegacyResponse(response);
      }
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
        if (response.affectedRows != null)
          'affected_rows': response.affectedRows,
        if (response.columnMetadata != null)
          'column_metadata': response.columnMetadata,
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

  /// Sends response using legacy envelope protocol.
  Future<Result<void>> _sendLegacyResponse(QueryResponse response) async {
    try {
      final envelope = _queryResponseToEnvelope(response);
      final envelopeData = envelope.toJson();
      _logMessage('SENT', 'query:response', envelopeData);
      _socket!.emit('query:response', envelopeData);

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to send legacy response',
          cause: e,
          context: {'operation': 'sendLegacyResponse'},
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

    if (!request.method.startsWith('sql.')) {
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
    final reason = errorData is Map<String, dynamic>
        ? (errorData['reason'] as String?)
        : null;

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

  void _startHeartbeat() {
    _stopHeartbeat();
    _missedHeartbeats = 0;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
    });
    _sendHeartbeat();
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatAckTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatAckTimer = null;
    _isWaitingHeartbeatAck = false;
  }

  void _sendHeartbeat() {
    if (_socket == null || !_socket!.connected) {
      return;
    }

    if (_isWaitingHeartbeatAck) {
      _handleHeartbeatTimeout();
      return;
    }

    _isWaitingHeartbeatAck = true;
    final payload = <String, dynamic>{
      'agent_id': _agentId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'protocol': _currentProtocol.protocol,
    };
    _logMessage('SENT', 'agent:heartbeat', payload);
    _socket!.emit('agent:heartbeat', payload);

    _heartbeatAckTimer?.cancel();
    _heartbeatAckTimer = Timer(_heartbeatAckTimeout, _handleHeartbeatTimeout);
  }

  void _handleHeartbeatAck(dynamic data) {
    _heartbeatAckTimer?.cancel();
    _isWaitingHeartbeatAck = false;
    _missedHeartbeats = 0;
    _logMessage('RECEIVED', 'hub:heartbeat_ack', data);
  }

  void _handleHeartbeatTimeout() {
    _heartbeatAckTimer?.cancel();
    _isWaitingHeartbeatAck = false;
    _missedHeartbeats++;

    _logMessage('ERROR', 'heartbeat_timeout', {
      'agent_id': _agentId,
      'missed_heartbeats': _missedHeartbeats,
    });

    if (_missedHeartbeats < _maxMissedHeartbeats) {
      return;
    }

    _logMessage('ERROR', 'connection_stale', {
      'agent_id': _agentId,
      'reason': 'missed_heartbeat_ack',
      'missed_heartbeats': _missedHeartbeats,
    });
    _stopHeartbeat();
    _onReconnectionNeeded?.call();
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

  Map<String, dynamic> _prepareResponseForSend(RpcResponse response) {
    if (!_featureFlags.enableSocketApiVersionMeta) {
      return response.toJson();
    }
    final json = Map<String, dynamic>.from(response.toJson());
    json['api_version'] = '2.1';
    json['meta'] = <String, dynamic>{
      'agent_id': _agentId,
      'request_id': response.id?.toString(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    return json;
  }

  Future<void> _sendSchemaValidationError(
    dynamic id,
    int code,
    String technicalMessage,
  ) async {
    final errorResponse = _buildRpcErrorResponse(
      id: id,
      code: code,
      technicalMessage: technicalMessage,
    );
    await _emitRpcResponse(errorResponse);
  }

  RpcResponse _buildRpcErrorResponse({
    required dynamic id,
    required int code,
    required String technicalMessage,
  }) {
    return RpcResponse.error(
      id: id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: technicalMessage,
        ),
      ),
    );
  }

  String? _extractClientTokenFromRpcParams(dynamic params) {
    if (params is! Map<String, dynamic>) return null;
    final raw =
        params['client_token'] as String? ??
        params['auth'] as String? ??
        params['clientToken'] as String?;
    return raw != null && raw.trim().isNotEmpty ? raw.trim() : null;
  }

  QueryRequest _envelopeToQueryRequest(EnvelopeModel envelope) {
    final payload = envelope.payloadBytes.isNotEmpty
        ? envelope.payloadBytes.first
        : <String, dynamic>{};

    final rawToken =
        payload['client_token'] as String? ??
        payload['auth'] as String? ??
        payload['token'] as String?;
    final clientToken = rawToken != null && rawToken.trim().isNotEmpty
        ? rawToken.trim()
        : null;

    return QueryRequest(
      id: envelope.requestId,
      agentId: envelope.agentId,
      query: payload['query'] as String? ?? '',
      parameters: payload['parameters'] as Map<String, dynamic>?,
      timestamp: envelope.timestamp,
      clientToken: clientToken,
    );
  }

  EnvelopeModel _queryResponseToEnvelope(QueryResponse response) {
    // Detect if data is compressed
    final isCompressed =
        response.data.length == 1 &&
        response.data.first.containsKey('compressed_data') &&
        (response.data.first['is_compressed'] as bool? ?? false);

    return EnvelopeModel(
      v: 1,
      type: 'query_response',
      requestId: response.id,
      agentId: response.agentId,
      timestamp: response.timestamp,
      cmp: isCompressed ? 'gzip' : 'none',
      contentType: 'json',
      payloadBytes: response.data,
    );
  }
}

class _SocketRpcStreamEmitter implements IRpcStreamEmitter {
  _SocketRpcStreamEmitter(this._socket, this._logMessage);

  final io.Socket? _socket;
  final void Function(String direction, String event, dynamic data) _logMessage;

  @override
  void emitChunk(RpcStreamChunk chunk) {
    final payload = chunk.toJson();
    _logMessage('SENT', 'rpc:chunk', payload);
    _socket?.emit('rpc:chunk', payload);
  }

  @override
  void emitComplete(RpcStreamComplete complete) {
    final payload = complete.toJson();
    _logMessage('SENT', 'rpc:complete', payload);
    _socket?.emit('rpc:complete', payload);
  }
}
