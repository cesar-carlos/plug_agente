import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_transport_connection_error_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_socket_event_binder.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Socket connect/disconnect lifecycle for the v2 Socket.IO transport client.
final class TransportConnectionLifecycle {
  TransportConnectionLifecycle({
    required SocketDataSource dataSource,
    required SocketIoTransportConnectionErrorHandler connectionErrorHandler,
    required TransportSocketEventBinder socketEventBinder,
    required CapabilitiesNegotiator capabilitiesNegotiator,
    required TransportPipelineCache pipelineCache,
    required TransportLocalCapabilitiesBuilder localCapabilitiesBuilder,
    required RpcRequestGuard requestGuard,
    required RpcInboundHandler inboundHandler,
    required RpcStreamPullHandler streamPullHandler,
    required AuthorizationDecisionLogger authorizationDecisionLogger,
    required IRpcRequestDispatcher rpcDispatcher,
    required VoidCallback heartbeatStop,
    required ResilienceLogPrefix resilienceLogPrefix,
    required HubLifecycleCallback? onHubLifecycle,
    required VoidCallback? onReconnectionNeeded,
    required void Function(String stage) publishPayloadSigningDiagnostic,
    required bool Function() binaryPayloadEnabled,
  }) : _dataSource = dataSource,
       _connectionErrorHandler = connectionErrorHandler,
       _socketEventBinder = socketEventBinder,
       _capabilitiesNegotiator = capabilitiesNegotiator,
       _pipelineCache = pipelineCache,
       _localCapabilitiesBuilder = localCapabilitiesBuilder,
       _requestGuard = requestGuard,
       _inboundHandler = inboundHandler,
       _streamPullHandler = streamPullHandler,
       _authorizationDecisionLogger = authorizationDecisionLogger,
       _rpcDispatcher = rpcDispatcher,
       _heartbeatStop = heartbeatStop,
       _resilienceLogPrefix = resilienceLogPrefix,
       _onHubLifecycle = onHubLifecycle,
       _onReconnectionNeeded = onReconnectionNeeded,
       _publishPayloadSigningDiagnostic = publishPayloadSigningDiagnostic,
       _binaryPayloadEnabled = binaryPayloadEnabled;

  final SocketDataSource _dataSource;
  final SocketIoTransportConnectionErrorHandler _connectionErrorHandler;
  final TransportSocketEventBinder _socketEventBinder;
  final CapabilitiesNegotiator _capabilitiesNegotiator;
  final TransportPipelineCache _pipelineCache;
  final TransportLocalCapabilitiesBuilder _localCapabilitiesBuilder;
  final RpcRequestGuard _requestGuard;
  final RpcInboundHandler _inboundHandler;
  final RpcStreamPullHandler _streamPullHandler;
  final AuthorizationDecisionLogger _authorizationDecisionLogger;
  final IRpcRequestDispatcher _rpcDispatcher;
  final VoidCallback _heartbeatStop;
  final ResilienceLogPrefix _resilienceLogPrefix;
  final HubLifecycleCallback? _onHubLifecycle;
  final VoidCallback? _onReconnectionNeeded;
  final void Function(String stage) _publishPayloadSigningDiagnostic;
  final bool Function() _binaryPayloadEnabled;

  io.Socket? socket;
  int connectGeneration = 0;
  String agentId = '';
  ProtocolConfig currentProtocol = const ProtocolConfig(
    protocol: 'jsonrpc-v2',
    encoding: 'json',
    compression: 'none',
  );

  bool get isConnected => socket?.connected ?? false;

  Future<Result<void>> connect(
    String serverUrl,
    String nextAgentId, {
    String? authToken,
  }) async {
    final nextGeneration = ++connectGeneration;
    try {
      if (!_binaryPayloadEnabled()) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Binary PayloadFrame transport is required by the current socket contract.',
            context: {'operation': 'connect', 'feature': 'enableBinaryPayload'},
          ),
        );
      }

      _heartbeatStop();
      closeSocket();

      agentId = nextAgentId;
      _capabilitiesNegotiator.reset();
      currentProtocol = const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
      );
      _publishPayloadSigningDiagnostic('connect_start');

      socket = _dataSource.createSocket(serverUrl, authToken: authToken);

      final completer = Completer<Result<void>>();
      Timer? timeoutTimer;

      _socketEventBinder.bind(
        socket: socket!,
        connectGeneration: nextGeneration,
        connectCompleter: completer,
        cancelConnectTimeout: () => timeoutTimer?.cancel(),
      );

      socket!.connect();

      AppLogger.info(
        'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_started '
        'agent_id=$agentId',
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
              'agent_id=$agentId',
            );
            closeSocket();
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
        'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_exception agent_id=$agentId',
        e,
      );
      closeSocket();
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to connect to server',
          cause: e,
          context: {'operation': 'connect'},
        ),
      );
    }
  }

  Future<Result<void>> disconnect() async {
    try {
      connectGeneration++;
      _heartbeatStop();
      closeSocket();
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

  void handleDisconnect(dynamic reason) {
    _heartbeatStop();
    final asString = reason is String ? reason : reason?.toString();
    final serverInitiated = isHubIoServerInitiatedDisconnect(asString);
    final disconnectLine =
        'resilience: ${_resilienceLogPrefix()}socket_transport event=disconnect '
        'kind=${serverInitiated ? "io_server_disconnect" : "client_or_network"} '
        'reason=${asString ?? "unknown"} agent_id=$agentId '
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

  void closeSocket() {
    _socketEventBinder.clearSubscriptions();
    _capabilitiesNegotiator.reset();
    _pipelineCache.reset();
    _localCapabilitiesBuilder.invalidateCache();
    _requestGuard.clearReplayCache();
    unawaited(
      _rpcDispatcher.cancelActiveStreamOnDisconnect().catchError((Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'Failed to cancel active stream on socket disconnect',
          error,
          stackTrace,
        );
      }),
    );
    final activeSocket = socket;
    socket = null;
    _streamPullHandler.dispose();
    _inboundHandler.resetAckBuffer();
    if (activeSocket == null) {
      return;
    }
    activeSocket.disconnect();
    activeSocket.dispose();
  }
}

typedef ResilienceLogPrefix = String Function();
typedef HubLifecycleCallback = void Function(HubLifecycleNotification notification);
typedef VoidCallback = void Function();
