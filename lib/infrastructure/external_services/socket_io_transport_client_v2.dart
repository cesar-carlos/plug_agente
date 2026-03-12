import 'dart:async';

import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/models/envelope_model.dart';
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

      _socket!.connect();

      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          _socket?.dispose();
          _socket = null;
          completer.complete(
            Failure(domain.NetworkFailure('Connection timeout')),
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
      // Check if it's a batch
      if (data is List) {
        await _handleRpcBatchRequest(data);
        return;
      }

      // Single request
      final request = RpcRequest.fromJson(data as Map<String, dynamic>);
      final guardResult = _rpcRequestGuard.evaluate(request);
      if (guardResult != RpcRequestGuardResult.allow) {
        final errorResponse = _buildRpcErrorResponse(
          id: request.id,
          code: _guardResultToCode(guardResult),
          technicalMessage: _guardResultToTechnicalMessage(guardResult),
        );
        _logMessage('SENT', 'rpc:response', errorResponse.toJson());
        _socket?.emit('rpc:response', errorResponse.toJson());
        return;
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

      // Send response
      _logMessage('SENT', 'rpc:response', response.toJson());
      _socket!.emit('rpc:response', response.toJson());
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'Error processing RPC request',
        error,
        stackTrace,
      );

      // Send parse error
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

      _socket!.emit('rpc:response', errorResponse.toJson());
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
        _socket!.emit('rpc:response', errorResponse.toJson());
        return;
      }

      final requests = data
          .map((e) => RpcRequest.fromJson(e as Map<String, dynamic>))
          .toList();

      final responses = <RpcResponse>[];

      for (final request in requests) {
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
      final batchResponse = responses.map((r) => r.toJson()).toList();
      _logMessage('SENT', 'rpc:response', batchResponse);
      _socket!.emit('rpc:response', batchResponse);
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

      _logMessage('SENT', 'rpc:response', rpcResponse.toJson());
      _socket!.emit('rpc:response', rpcResponse.toJson());

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
