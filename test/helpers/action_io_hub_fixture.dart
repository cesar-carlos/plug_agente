import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/actions/action_io_catalog.dart';
import 'package:plug_agente/application/actions/action_io_remote_access.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/rpc/action_io_rpc_handler.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/action_io_rpc_contract.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import 'e2e_env.dart';

class _UnusedDatabase extends Mock implements IDatabaseGateway {}

class _UnusedNormalizer extends Mock implements QueryNormalizerService {}

class _UnusedSqlAuthorization extends Mock implements AuthorizeSqlOperation {}

class _UnusedPolicy extends Mock implements GetClientTokenPolicy {}

class _UnusedConnectionStrings extends Mock implements IConfigConnectionStringSource {}

class _ObservedRunHandler implements RpcMethodHandler {
  _ObservedRunHandler(this.delegate, this.completed);
  final RpcMethodHandler delegate;
  final void Function(RpcResponse) completed;
  @override
  String get method => delegate.method;
  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    final response = await delegate.handle(request, context);
    completed(response);
    return response;
  }
}

/// Owned loopback hub only; no operational environment or credentials are loaded.
final class ActionIoHubFixture {
  ActionIoHubFixture._(this._manifest);
  final Map<String, dynamic> _manifest;
  SocketIOTransportClientV2? _transport;
  io.Socket? _consumer;
  String? _conversationId;
  String credential = 'fixture';
  final _runObservations = <String, Completer<RpcResponse>>{};
  Future<RpcResponse> observeRun(String id) {
    final observation = Completer<RpcResponse>();
    if (_runObservations.containsKey(id)) throw StateError('Duplicate fixture observation.');
    _runObservations[id] = observation;
    return observation.future;
  }

  bool get _relay => E2EEnv.get('ACTION_IO_CALLER_TRANSPORT') == 'relay';
  final _http = HttpClient();
  String get agentId => _manifest['agentId'] as String;
  String get clientId => _manifest['clientId'] as String;
  String get fixtureRoot => _manifest['root'] as String;

  static ActionIoHubFixture? fromEnvironment() {
    final path = E2EEnv.get('ACTION_IO_HUB_MANIFEST');
    if (path == null) return null;
    final file = File(path);
    final root = file.parent.resolveSymbolicLinksSync();
    if (p.dirname(root) != Directory.systemTemp.resolveSymbolicLinksSync() ||
        !RegExp(r'^plug-action-io-[a-f0-9-]{36}$').hasMatch(p.basename(root)) ||
        p.basename(path) != 'hub-ready.json' ||
        file.lengthSync() > 16384) {
      throw StateError('Invalid private hub manifest path.');
    }
    final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final uri = Uri.parse(manifest['hubUrl'] as String);
    if (manifest['format'] != 'action-io-hub-fixture-v1' ||
        manifest['root'] != root ||
        manifest['productionEnabled'] != false ||
        uri.scheme != 'http' ||
        uri.host != '127.0.0.1') {
      throw StateError('Only the isolated loopback hub is accepted.');
    }
    return ActionIoHubFixture._(manifest);
  }

  Future<void> connect({
    required ActionIoRpcHandler run,
    required ActionIoRpcHandler validate,
    required ActionIoCatalog catalog,
    required ActionIoRemoteAccess access,
    required ActionIoRpcContract contract,
  }) async {
    final flags = FeatureFlags(
      InMemoryAppSettingsStore({
        'feature_enable_agent_actions': true,
        'feature_enable_remote_agent_actions': true,
        'feature_enable_action_io': true,
      }),
    );
    final database = _UnusedDatabase();
    final observedRun = _ObservedRunHandler(run, (response) {
      _runObservations.remove(response.id)?.complete(response);
    });
    final handlers = [
      observedRun,
      for (final method in {...ActionIoRpcHandler.methods, 'agent.action.getExecution', 'agent.action.cancel'})
        ActionIoRpcHandler(method, contract: contract, enabled: () => true, access: access, catalog: () => catalog),
    ];
    final dispatcher = RpcMethodDispatcher(
      databaseGateway: database,
      healthService: HealthService(metricsCollector: MetricsCollector(), gateway: database),
      normalizerService: _UnusedNormalizer(),
      uuid: const Uuid(),
      authorizeSqlOperation: _UnusedSqlAuthorization(),
      getClientTokenPolicy: _UnusedPolicy(),
      getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 60),
      connectionStringSource: _UnusedConnectionStrings(),
      featureFlags: flags,
      handlers: handlers,
      actionIoRunHandler: observedRun,
      actionIoValidateHandler: validate,
    );
    final registered = Completer<void>();
    final transport = SocketIOTransportClientV2(
      dataSource: SocketDataSource(),
      negotiator: ProtocolNegotiator(),
      rpcDispatcher: dispatcher,
      featureFlags: flags,
      options: SocketIOTransportClientV2Options(
        agentActionsRemoteCapabilityProvider: AgentActionsRemoteCapabilityProvider(
          runtimeStateGuard: AgentActionRuntimeStateGuard(),
          elevatedRunnerReadiness: ElevatedActionRunnerReadinessService(),
          faithfulIoAvailable: () => true,
        ),
      ),
    );
    _transport = transport;
    transport.setMessageCallback((direction, event, data) {
      if (event == 'agent:ready' && !registered.isCompleted) registered.complete();
    });
    (await transport.connect(
      _manifest['hubUrl'] as String,
      agentId,
      authToken: _manifest['agentAuthToken'] as String,
    )).getOrThrow();
    await registered.future.timeout(const Duration(seconds: 15));
    if (E2EEnv.get('ACTION_IO_CALLER_TRANSPORT') == 'socket' || _relay) {
      final ready = Completer<void>();
      final consumer = io.io(
        '${_manifest['hubUrl']}/consumers',
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': _manifest['clientAccessToken']})
            .disableAutoConnect()
            .disableReconnection()
            .enableForceNew()
            .build(),
      );
      _consumer = consumer;
      consumer.on('connection:ready', (_) {
        if (!ready.isCompleted) ready.complete();
      });
      consumer.on('connect_error', (_) {
        if (!ready.isCompleted) ready.completeError(StateError('Fixture consumer connection refused.'));
      });
      consumer.connect();
      await ready.future.timeout(const Duration(seconds: 10));
      if (_relay) await _startConversation();
    }
  }

  Future<RpcResponse> call(RpcRequest command, {int timeoutMs = 30000}) async {
    if (_consumer != null) return _callSocket(command, timeoutMs: timeoutMs);
    final request = await _http.postUrl(Uri.parse('${_manifest['hubUrl']}/api/v1/agents/commands'));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_manifest['clientAccessToken']}');
    request.write(
      jsonEncode({
        'agentId': agentId,
        'timeoutMs': timeoutMs,
        'command': {
          ...command.toJson(),
          'params': {...(command.params as Map<String, dynamic>), 'client_token': credential},
        },
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 1024 * 1024) throw StateError('Fixture HTTP response exceeds limit.');
      bytes.addAll(chunk);
    }
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final normalized = body['response'];
    if (normalized is! Map || normalized['type'] != 'single') {
      throw StateError(
        'Fixture bridge refused request: HTTP ${response.statusCode}, code ${body['error'] is Map ? (body['error'] as Map)['code'] : body['code']}',
      );
    }
    final item = normalized['item'] as Map<String, dynamic>;
    return RpcResponse.fromJson({
      'jsonrpc': '2.0',
      'id': item['id'],
      if (item['success'] == true) 'result': item['result'] else 'error': item['error'],
    });
  }

  Future<void> verifyReferenceClient(String actionId) async {
    final pending = File(p.join(fixtureRoot, 'reference-request.next'));
    final request = File(p.join(fixtureRoot, 'reference-request.json'));
    final result = File(p.join(fixtureRoot, 'reference-result.json'));
    if (request.existsSync() || pending.existsSync() || result.existsSync()) {
      throw StateError('Reference fixture must run once in a fresh private session.');
    }
    try {
      await pending.writeAsString(
        jsonEncode({
          'format': 'action-io-reference-v1',
          'actionId': actionId,
          'credential': credential,
        }),
        flush: true,
      );
      await pending.rename(request.path);
      final deadline = DateTime.now().add(const Duration(seconds: 100));
      while (!result.existsSync()) {
        if (!DateTime.now().isBefore(deadline)) throw StateError('Reference client fixture timed out.');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (result.lengthSync() > 16384) throw StateError('Reference result exceeds fixture limit.');
      final report = jsonDecode(await result.readAsString()) as Map<String, dynamic>;
      if (report['success'] != true || jsonEncode(report['transports']) != '["rest","socket","relay"]') {
        throw StateError('Reference client fixture failed (${report['error']}).');
      }
    } finally {
      if (pending.existsSync()) await pending.delete();
      if (request.existsSync()) await request.delete();
    }
  }

  Future<RpcResponse> _callSocket(RpcRequest command, {required int timeoutMs}) async {
    final socket = _consumer!;
    if (!socket.connected) throw StateError('Consumer disconnected; no command was sent.');
    final result = Completer<RpcResponse>();
    void disconnected(dynamic _) {
      if (!result.isCompleted) result.completeError(StateError('Consumer disconnected; reconcile outcome.'));
    }

    Future<void> received(dynamic raw) async {
      try {
        final frame = PayloadFrame.fromJson(Map<String, dynamic>.from(raw as Map));
        final decoded =
            (await TransportPipeline(
                  encoding: frame.enc,
                  compression: frame.cmp,
                ).receiveProcessAsync(frame)).getOrThrow()
                as Map<String, dynamic>;
        if (_relay) {
          if (decoded['id'] == command.id && !result.isCompleted) {
            result.complete(RpcResponse.fromJson(decoded));
          }
          return;
        }
        final response = decoded['response'];
        if (response is! Map || response['type'] != 'single') {
          if (decoded['requestId'] == command.id && !result.isCompleted) {
            final error = decoded['error'];
            final code = error is Map ? error['code'] : null;
            result.completeError(StateError('Consumer command refused (${command.method}, code=$code).'));
          }
          return;
        }
        final item = Map<String, dynamic>.from(response['item'] as Map);
        if (item['id'] != command.id || result.isCompleted) return;
        result.complete(
          RpcResponse.fromJson({
            'jsonrpc': '2.0',
            'id': item['id'],
            if (item['success'] == true) 'result': item['result'] else 'error': item['error'],
          }),
        );
      } on Object catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    }

    final responseEvent = _relay ? 'relay:rpc.response' : 'agents:command_response';
    void accepted(dynamic raw) {
      if (raw is Map && raw['conversationId'] == _conversationId && raw['success'] == false && !result.isCompleted) {
        final error = raw['error'];
        final code = error is Map ? error['code'] : null;
        result.completeError(StateError('Relay command refused (${command.method}, code=$code).'));
      }
    }

    if (_relay) socket.on('relay:rpc.accepted', accepted);
    socket.on(responseEvent, received);
    socket.on('disconnect', disconnected);
    try {
      final payload = {
        ...command.toJson(),
        'params': {...(command.params as Map<String, dynamic>), 'client_token': credential},
      };
      if (_relay) {
        final frame = (await TransportPipeline(
          encoding: 'json',
          compression: 'none',
        ).prepareSendAsync(payload)).getOrThrow();
        socket.emit('relay:rpc.request', {
          'conversationId': _conversationId,
          'frame': frame.toJson(),
          'timeoutMs': timeoutMs,
          'fastPath': true,
        });
      } else {
        socket.emit('agents:command', {
          'agentId': agentId,
          'timeoutMs': timeoutMs,
          'command': payload,
        });
      }
      return await result.future.timeout(const Duration(seconds: 30));
    } finally {
      socket.off(responseEvent, received);
      if (_relay) socket.off('relay:rpc.accepted', accepted);
      socket.off('disconnect', disconnected);
    }
  }

  Future<void> _startConversation() async {
    final result = Completer<String>();
    Future<void> started(dynamic raw) async {
      try {
        // Relay conversation control uses its documented plain JSON envelope.
        final body = Map<String, dynamic>.from(raw as Map);
        if (body['success'] != true || body['agentId'] != agentId || body['conversationId'] is! String) {
          throw StateError('Fixture relay conversation refused.');
        }
        if (!result.isCompleted) result.complete(body['conversationId'] as String);
      } on Object catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    }

    _consumer!.on('relay:conversation.started', started);
    try {
      _consumer!.emit('relay:conversation.start', {'agentId': agentId});
      _conversationId = await result.future.timeout(const Duration(seconds: 10));
    } finally {
      _consumer!.off('relay:conversation.started', started);
    }
  }

  Future<void> reconnectCaller() async {
    final socket = _consumer;
    if (socket == null) return;
    socket.disconnect();
    final ready = Completer<void>();
    void connected(dynamic _) {
      if (!ready.isCompleted) ready.complete();
    }

    void failed(dynamic _) {
      if (!ready.isCompleted) ready.completeError(StateError('Fixture consumer reconnection refused.'));
    }

    socket.on('connection:ready', connected);
    socket.on('connect_error', failed);
    try {
      socket.connect();
      await ready.future.timeout(const Duration(seconds: 10));
      if (_relay) await _startConversation();
    } finally {
      socket.off('connection:ready', connected);
      socket.off('connect_error', failed);
    }
  }

  Future<void> close() async {
    _http.close(force: true);
    _consumer?.dispose();
    await _transport?.disconnect();
  }
}
