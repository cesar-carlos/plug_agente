import 'dart:async';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Wires Socket.IO transport events and manager-level reconnect callbacks.
///
/// Keeps `SocketIOTransportClientV2` focused on protocol orchestration while
/// this collaborator owns listener registration and reconnect bookkeeping.
class TransportSocketEventBinder {
  TransportSocketEventBinder({
    required FeatureFlags featureFlags,
    required RpcInboundHandler inboundHandler,
    required CapabilitiesNegotiator capabilitiesNegotiator,
    required RpcStreamPullHandler streamPullHandler,
    required void Function(String direction, String event, dynamic data) logMessage,
    required String Function() agentIdProvider,
    required String Function() resilienceLogPrefixProvider,
    required int Function() connectGenerationProvider,
    required bool Function(int generation) isStaleConnectGeneration,
    required void Function() onAuthorizationSessionReset,
    required void Function() onHeartbeatResetTransient,
    required Future<bool> Function() onTransportConnectedRegister,
    required void Function() onHeartbeatStop,
    required void Function() onCloseSocket,
    required void Function(dynamic error, Completer<Result<void>> completer) onConnectError,
    required void Function(dynamic error) onSocketError,
    required void Function(dynamic reason) onDisconnect,
    required void Function(dynamic data) onCapabilitiesEnvelope,
    required void Function(dynamic data) onHeartbeatAck,
    required void Function()? onReconnectionNeeded,
    required void Function(HubLifecycleNotification notification)? onHubLifecycle,
    required bool Function() hasMessageCallback,
    required Future<void> Function() sendReRegisterAfterReconnect,
  }) : _featureFlags = featureFlags,
       _inboundHandler = inboundHandler,
       _capabilitiesNegotiator = capabilitiesNegotiator,
       _streamPullHandler = streamPullHandler,
       _logMessage = logMessage,
       _agentIdProvider = agentIdProvider,
       _resilienceLogPrefixProvider = resilienceLogPrefixProvider,
       _connectGenerationProvider = connectGenerationProvider,
       _isStaleConnectGeneration = isStaleConnectGeneration,
       _onAuthorizationSessionReset = onAuthorizationSessionReset,
       _onHeartbeatResetTransient = onHeartbeatResetTransient,
       _onTransportConnectedRegister = onTransportConnectedRegister,
       _onHeartbeatStop = onHeartbeatStop,
       _onCloseSocket = onCloseSocket,
       _onConnectError = onConnectError,
       _onSocketError = onSocketError,
       _onDisconnect = onDisconnect,
       _onCapabilitiesEnvelope = onCapabilitiesEnvelope,
       _onHeartbeatAck = onHeartbeatAck,
       _onReconnectionNeeded = onReconnectionNeeded,
       _onHubLifecycle = onHubLifecycle,
       _hasMessageCallback = hasMessageCallback,
       _sendReRegisterAfterReconnect = sendReRegisterAfterReconnect;

  final FeatureFlags _featureFlags;
  final RpcInboundHandler _inboundHandler;
  final CapabilitiesNegotiator _capabilitiesNegotiator;
  final RpcStreamPullHandler _streamPullHandler;
  final void Function(String direction, String event, dynamic data) _logMessage;
  final String Function() _agentIdProvider;
  final String Function() _resilienceLogPrefixProvider;
  final int Function() _connectGenerationProvider;
  final bool Function(int generation) _isStaleConnectGeneration;
  final void Function() _onAuthorizationSessionReset;
  final void Function() _onHeartbeatResetTransient;
  final Future<bool> Function() _onTransportConnectedRegister;
  final void Function() _onHeartbeatStop;
  final void Function() _onCloseSocket;
  final void Function(dynamic error, Completer<Result<void>> completer) _onConnectError;
  final void Function(dynamic error) _onSocketError;
  final void Function(dynamic reason) _onDisconnect;
  final void Function(dynamic data) _onCapabilitiesEnvelope;
  final void Function(dynamic data) _onHeartbeatAck;
  final void Function()? _onReconnectionNeeded;
  final void Function(HubLifecycleNotification notification)? _onHubLifecycle;
  final bool Function() _hasMessageCallback;
  final Future<void> Function() _sendReRegisterAfterReconnect;

  final List<void Function()> _managerReconnectSubscriptions = <void Function()>[];

  String get _agentId => _agentIdProvider();

  String _resilienceLogPrefix() => _resilienceLogPrefixProvider();

  void bind({
    required io.Socket socket,
    required int connectGeneration,
    required Completer<Result<void>> connectCompleter,
    required void Function() cancelConnectTimeout,
  }) {
    socket.on('connect', (_) async {
      if (_isStaleConnectGeneration(connectGeneration)) {
        AppLogger.debug(
          'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_ignored_stale_generation '
          'generation=$connectGeneration current=${_connectGenerationProvider()} agent_id=$_agentId',
        );
        return;
      }
      cancelConnectTimeout();
      _logMessage('RECEIVED', 'connect', null);
      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}socket_transport event=transport_connected agent_id=$_agentId',
      );
      _onAuthorizationSessionReset();
      _onHeartbeatResetTransient();
      final registerSent = await _onTransportConnectedRegister();
      if (!registerSent) {
        _onHeartbeatStop();
        _onCloseSocket();
        if (!connectCompleter.isCompleted) {
          connectCompleter.complete(
            Failure(
              domain.ConfigurationFailure.withContext(
                message: 'Failed to send agent registration to hub.',
                context: {
                  'operation': 'agent_register',
                  'agent_id': _agentId,
                },
              ),
            ),
          );
        }
        return;
      }

      if (!connectCompleter.isCompleted) {
        connectCompleter.complete(const Success<Object, Exception>(Object()));
      }
    });

    registerManagerReconnectHandlers(socket);

    socket.on('connect_error', (error) {
      cancelConnectTimeout();
      _logMessage('ERROR', 'connect_error', error);
      _onConnectError(error, connectCompleter);
    });

    socket.on('error', (error) {
      _logMessage('ERROR', 'socket_error', error);
      _onSocketError(error);
    });

    socket.on('disconnect', (dynamic reason) {
      // Guard against stale disconnect events from a previous socket that
      // fires after a new connect() has incremented the generation. Without
      // this guard, the old socket's disconnect would trigger recovery while
      // the new connection is already in progress (hub audit C1 / r1-1).
      if (_isStaleConnectGeneration(connectGeneration)) {
        AppLogger.debug(
          'resilience: ${_resilienceLogPrefix()}socket_transport '
          'event=disconnect_ignored_stale_generation '
          'generation=$connectGeneration current=${_connectGenerationProvider()} '
          'reason=$reason',
        );
        return;
      }
      _logMessage('RECEIVED', 'disconnect', reason);
      _onDisconnect(reason);
    });

    socket.on('agent:capabilities', (data) {
      _logMessage('RECEIVED', 'agent:capabilities', data);
      _onCapabilitiesEnvelope(data);
    });

    socket.on('agent:register_error', (data) {
      _logMessage('RECEIVED', 'agent:register_error', data);
      final map = data is Map ? data.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};
      final shouldReconnect = _capabilitiesNegotiator.handleRegisterError(map);
      if (shouldReconnect) {
        _onHeartbeatStop();
        _onCloseSocket();
      }
    });

    socket.on('hub:heartbeat_ack', _onHeartbeatAck);

    socket.on('rpc:request', (data) {
      if (_hasMessageCallback()) {
        _logMessage('RECEIVED', 'rpc:request', data);
      }
      if (!_inboundHandler.tryAcquireSlot()) {
        unawaited(_inboundHandler.emitConcurrencyLimitedError(data));
        return;
      }
      unawaited(_inboundHandler.handleRequestWithRelease(data));
    });

    // Register rpc:stream.pull whenever any streaming path is active: the hub
    // may send pull credits even when the backpressure flag is off but chunked
    // or DB streaming is enabled; silently dropping them would stall streams.
    if (_featureFlags.enableSocketBackpressure ||
        _featureFlags.enableSocketStreamingChunks ||
        _featureFlags.enableSocketStreamingFromDb) {
      socket.on('rpc:stream.pull', (data) {
        _logMessage('RECEIVED', 'rpc:stream.pull', data);
        _streamPullHandler.handlePull(data);
      });
    }
  }

  void registerManagerReconnectHandlers(io.Socket socket) {
    clearSubscriptions();
    _managerReconnectSubscriptions
      ..add(
        io.DartySocket(socket).onReconnect((dynamic data) {
          unawaited(_handleManagerReconnect(data));
        }),
      )
      ..add(io.DartySocket(socket).onReconnectAttempt(_handleManagerReconnectAttempt))
      ..add(
        io.DartySocket(socket).onReconnectFailed((_) {
          _handleManagerReconnectFailed();
        }),
      )
      ..add(io.DartySocket(socket).onReconnectError(_handleManagerReconnectError));
  }

  Future<void> _handleManagerReconnect(dynamic data) async {
    final generationAtEvent = _connectGenerationProvider();
    _logMessage('RECEIVED', 'reconnect', data);
    AppLogger.info(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=transport_reconnected '
      'attempt=${_parseReconnectAttempt(data)} agent_id=$_agentId',
    );
    if (_isStaleConnectGeneration(generationAtEvent)) {
      AppLogger.debug(
        'resilience: ${_resilienceLogPrefix()}socket_transport event=manager_reconnect_ignored_stale_generation '
        'generation=$generationAtEvent current=${_connectGenerationProvider()} agent_id=$_agentId',
      );
      return;
    }
    _onHeartbeatResetTransient();
    try {
      await _sendReRegisterAfterReconnect();
      if (_isStaleConnectGeneration(generationAtEvent)) {
        AppLogger.debug(
          'resilience: ${_resilienceLogPrefix()}socket_transport event=manager_reconnect_register_ignored_stale_generation '
          'generation=$generationAtEvent current=${_connectGenerationProvider()} agent_id=$_agentId',
        );
        return;
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'resilience: ${_resilienceLogPrefix()}socket_transport event=post_reconnect_register_failed '
        'agent_id=$_agentId',
        error,
        stackTrace,
      );
      _onReconnectionNeeded?.call();
    }
  }

  void _handleManagerReconnectAttempt(dynamic data) {
    _logMessage('RECEIVED', 'reconnect_attempt', data);
    final attempt = _parseReconnectAttempt(data);
    AppLogger.info(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=reconnect_attempt '
      'attempt=$attempt agent_id=$_agentId',
    );
    _onHubLifecycle?.call(HubTransportReconnectAttempt(attemptNumber: attempt));
  }

  void _handleManagerReconnectFailed() {
    _logMessage('ERROR', 'reconnect_failed', null);
    AppLogger.error(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=reconnect_exhausted '
      'agent_id=$_agentId - Socket.IO gave up after repeated transport reconnects; '
      'escalating to application-level hub recovery',
    );
    _onReconnectionNeeded?.call();
  }

  void _handleManagerReconnectError(dynamic error) {
    _logMessage('ERROR', 'reconnect_error', error);
    _onSocketError(error);
  }

  void clearSubscriptions() {
    for (final unsubscribe in _managerReconnectSubscriptions) {
      try {
        unsubscribe();
      } on Object catch (error, stackTrace) {
        AppLogger.warning(
          'Failed to remove Socket.IO manager reconnect subscription',
          error,
          stackTrace,
        );
      }
    }
    _managerReconnectSubscriptions.clear();
  }

  static int? _parseReconnectAttempt(dynamic data) {
    return data is int ? data : (data is num ? data.toInt() : int.tryParse('$data'));
  }
}
