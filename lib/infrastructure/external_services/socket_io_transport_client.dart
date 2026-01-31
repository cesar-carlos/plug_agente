import 'dart:async';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/models/envelope_model.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketIOTransportClient implements ITransportClient {
  SocketIOTransportClient(this._dataSource);
  final SocketDataSource _dataSource;

  io.Socket? _socket;
  String _agentId = '';
  final StreamController<QueryRequest> _queryRequestController =
      StreamController<QueryRequest>.broadcast();

  void Function(String direction, String event, dynamic data)? _onMessage;
  void Function()? _onTokenExpired;
  void Function()? _onReconnectionNeeded;

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
      // Limpar socket anterior se existir
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
        final registerData = {
          'agentId': _agentId,
          'timestamp': DateTime.now().toIso8601String(),
        };
        _logMessage('SENT', 'agent:register', registerData);
        _socket!.emit('agent:register', registerData);

        if (!completer.isCompleted) {
          completer.complete(const Success<Object, Exception>(Object()));
        }
      });

      _socket!.on('reconnect', (_) {
        _logMessage('RECEIVED', 'reconnect', null);
        final registerData = {
          'agentId': _agentId,
          'timestamp': DateTime.now().toIso8601String(),
        };
        _logMessage('SENT', 'agent:register', registerData);
        _socket!.emit('agent:register', registerData);
      });

      _socket!.on('reconnect_failed', (_) {
        _logMessage('ERROR', 'reconnect_failed', null);
        AppLogger.error('Reconnection failed after multiple attempts');
        _onReconnectionNeeded?.call();
      });

      _socket!.on('connect_error', (error) {
        timeoutTimer?.cancel();
        _logMessage('ERROR', 'connect_error', error);
        final errorMessage = error.toString();
        AppLogger.error('Connection error: $errorMessage');

        // Limpar socket em caso de erro para evitar reconexão
        _socket?.dispose();
        _socket = null;

        if (errorMessage.contains('Authentication') ||
            errorMessage.contains('Invalid token') ||
            errorMessage.contains('401')) {
          _onTokenExpired?.call();
        }

        if (!completer.isCompleted) {
          completer.complete(
            Failure(domain.NetworkFailure('Connection error: $errorMessage')),
          );
        }
      });

      _socket!.on('error', (error) {
        _logMessage('ERROR', 'socket_error', error);
        final errorMessage = error.toString();
        AppLogger.error('Socket error: $errorMessage');

        if (errorMessage.contains('Authentication') ||
            errorMessage.contains('Invalid token') ||
            errorMessage.contains('401')) {
          _onTokenExpired?.call();
        }
      });

      _socket!.on('disconnect', (reason) {
        _logMessage('RECEIVED', 'disconnect', reason);
        _socket = null;
      });

      _socket!.on('query:request', (data) {
        _logMessage('RECEIVED', 'query:request', data);
        try {
          final envelope = EnvelopeModel.fromJson(data as Map<String, dynamic>);
          final request = _envelopeToQueryRequest(envelope);
          _queryRequestController.add(request);
        } on Exception catch (e) {
          AppLogger.error('Error processing query request', e);
        }
      });

      _socket!.connect();

      // Timeout de 10 segundos para conexão
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
      return Failure(domain.NetworkFailure('Failed to connect to server: $e'));
    }
  }

  @override
  Future<Result<void>> disconnect() async {
    try {
      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
        _socket = null;
      }
      await _queryRequestController.close();
      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(domain.NetworkFailure('Failed to disconnect: $e'));
    }
  }

  @override
  Future<Result<void>> sendResponse(QueryResponse response) async {
    try {
      if (_socket == null || !_socket!.connected) {
        return Failure(domain.NetworkFailure('Not connected to server'));
      }

      final envelope = _queryResponseToEnvelope(response);
      final envelopeData = envelope.toJson();
      _logMessage('SENT', 'query:response', envelopeData);
      _socket!.emit('query:response', envelopeData);

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(domain.NetworkFailure('Failed to send response: $e'));
    }
  }

  QueryRequest _envelopeToQueryRequest(EnvelopeModel envelope) {
    // Extract query and parameters from payloadBytes
    // For query requests, payloadBytes should contain a map with 'query' and optionally 'parameters'
    final payload = envelope.payloadBytes.isNotEmpty
        ? envelope.payloadBytes.first
        : <String, dynamic>{};

    return QueryRequest(
      id: envelope.requestId,
      agentId: envelope.agentId,
      query: payload['query'] as String? ?? '',
      parameters: payload['parameters'] as Map<String, dynamic>?,
      timestamp: envelope.timestamp,
    );
  }

  EnvelopeModel _queryResponseToEnvelope(QueryResponse response) {
    return EnvelopeModel(
      v: 1,
      type: 'query_response',
      requestId: response.id,
      agentId: response.agentId,
      timestamp: response.timestamp,
      cmp: 'none',
      contentType: 'json',
      payloadBytes: response.data,
    );
  }
}
