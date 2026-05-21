import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../helpers/e2e_env.dart';

bool _looksLikePayloadFrameWire(Map<String, dynamic> m) =>
    m.containsKey('schemaVersion') &&
    m.containsKey('enc') &&
    m.containsKey('cmp') &&
    m.containsKey('payload') &&
    m.containsKey('originalSize') &&
    m.containsKey('compressedSize');

Future<RpcRequest?> _tryDecodeRpcRequestFromWire(dynamic data) async {
  if (data is! Map) {
    return null;
  }
  final m = Map<String, dynamic>.from(data);
  if (!_looksLikePayloadFrameWire(m)) {
    return null;
  }
  final frame = PayloadFrame.fromJson(m);
  final compression = frame.cmp == 'gzip' ? 'gzip' : 'none';
  final pipeline = TransportPipeline(
    encoding: frame.enc,
    compression: compression,
  );
  final result = await pipeline.receiveProcessAsync(frame);
  if (result.isError()) {
    return null;
  }
  final decoded = result.getOrThrow();
  if (decoded is! Map<String, dynamic>) {
    return null;
  }
  try {
    return RpcRequest.fromJson(decoded);
  } on Object {
    return null;
  }
}

Future<Map<String, dynamic>?> _decodeCapabilitiesLogical({
  required PayloadFrame frame,
  required TransportPipeline pipeline,
}) async {
  final compression = frame.cmp == 'gzip' ? 'gzip' : 'none';
  final decodePipeline = TransportPipeline(
    encoding: frame.enc,
    compression: compression,
  );
  final result = await decodePipeline.receiveProcessAsync(frame);
  if (result.isError()) {
    return null;
  }

  final decoded = result.getOrThrow();
  if (decoded is! Map<String, dynamic>) {
    return null;
  }

  return decoded;
}

Future<
  ({
    io.Socket socket,
    PayloadSigner signer,
    TransportPipeline pipeline,
    PayloadFrame capabilitiesFrame,
  })
> _openSessionAfterSignedCapabilities({
  required String hubUrl,
  required String hubToken,
  required String keyId,
  required String key,
}) async {
  final signer = PayloadSigner(keys: <String, String>{keyId: key}, activeKeyId: keyId);
  final pipeline = TransportPipeline(
    encoding: 'json',
    compression: 'auto',
  );
  final registerPayload = <String, dynamic>{
    'agentId': E2EEnv.e2eHubAgentId,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'capabilities': ProtocolCapabilities.defaultCapabilities(
      signatureRequired: true,
    ).toJson(),
  };
  final unsignedRegister = (await pipeline.prepareSendAsync(
    registerPayload,
    metricEventName: 'agent:register',
  )).getOrThrow();
  final signedRegister = unsignedRegister.copyWith(
    signature: signer.signFrame(unsignedRegister).toJson(),
  );

  final ds = SocketDataSource();
  final socket = ds.createSocket(hubUrl, authToken: hubToken);
  final connected = Completer<void>();
  final capabilities = Completer<PayloadFrame>();

  socket
    ..on('connect', (_) {
      if (!connected.isCompleted) {
        connected.complete();
      }
    })
    ..on('connect_error', (dynamic data) {
      if (!connected.isCompleted) {
        connected.completeError(
          StateError('connect_error from hub (check URL, token, and network): $data'),
        );
      }
    })
    ..on('agent:capabilities', (dynamic data) {
      if (capabilities.isCompleted) {
        return;
      }
      try {
        if (data is! Map<String, dynamic>) {
          throw StateError('agent:capabilities payload is not a map');
        }
        capabilities.complete(PayloadFrame.fromJson(data));
      } on Object catch (error, stackTrace) {
        capabilities.completeError(error, stackTrace);
      }
    });

  socket.connect();
  await connected.future.timeout(const Duration(seconds: 25));
  socket.emit('agent:register', signedRegister.toJson());
  final responseFrame = await capabilities.future.timeout(
    const Duration(seconds: 25),
    onTimeout: () {
      throw TimeoutException('agent:capabilities not received within 25s after signed register');
    },
  );
  final signatureJson = responseFrame.signature;
  expect(signatureJson, isNotNull, reason: 'Hub must sign agent:capabilities in this opt-in test');
  expect(
    signer.verifyFrame(responseFrame, PayloadSignature.fromJson(signatureJson!)),
    isTrue,
    reason: 'Hub agent:capabilities signature must verify with configured key id',
  );

  return (
    socket: socket,
    signer: signer,
    pipeline: pipeline,
    capabilitiesFrame: responseFrame,
  );
}

Future<void> _emitSignedAgentReady({
  required io.Socket socket,
  required PayloadSigner signer,
  required TransportPipeline pipeline,
}) async {
  final readyLogical = <String, dynamic>{
    'agent_id': E2EEnv.e2eHubAgentId,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'protocol': 'jsonrpc-v2',
  };
  final unsignedReady = (await pipeline.prepareSendAsync(
    readyLogical,
    metricEventName: 'agent:ready',
  )).getOrThrow();
  final signedReady = unsignedReady.copyWith(
    signature: signer.signFrame(unsignedReady).toJson(),
  );
  socket.emit('agent:ready', signedReady.toJson());
}

/// Opt-in live Socket.IO path: signed register/capabilities, then `agent:ready`
/// (PayloadFrame + transport signing, aligned with the app transport client), for
/// homologating the hub path before `agent.action.*` `rpc:request` traffic.
void main() async {
  await E2EEnv.load();

  final readinessSkip = E2EEnv.liveHubAgentActionReadinessSkipMessage;

  group('Hub agent.action RPC readiness (live E2E)', () {
    test(
      'should emit signed agent:ready after capabilities and stay connected',
      () async {
        final hubUrl = E2EEnv.e2eHubUrl!;
        final hubToken = E2EEnv.e2eHubToken!;
        final keyId = E2EEnv.e2ePayloadSigningKeyId!;
        final key = E2EEnv.e2ePayloadSigningKey!;

        final session = await _openSessionAfterSignedCapabilities(
          hubUrl: hubUrl,
          hubToken: hubToken,
          keyId: keyId,
          key: key,
        );
        try {
          await _emitSignedAgentReady(
            socket: session.socket,
            signer: session.signer,
            pipeline: session.pipeline,
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          expect(session.socket.connected, isTrue);
        } finally {
          session.socket.dispose();
        }
      },
      skip: readinessSkip,
      tags: const ['live'],
    );

    test(
      'should include agentActions in agent:capabilities when hub advertises it (E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY)',
      () async {
        final hubUrl = E2EEnv.e2eHubUrl!;
        final hubToken = E2EEnv.e2eHubToken!;
        final keyId = E2EEnv.e2ePayloadSigningKeyId!;
        final key = E2EEnv.e2ePayloadSigningKey!;

        final session = await _openSessionAfterSignedCapabilities(
          hubUrl: hubUrl,
          hubToken: hubToken,
          keyId: keyId,
          key: key,
        );
        try {
          final logical = await _decodeCapabilitiesLogical(
            frame: session.capabilitiesFrame,
            pipeline: session.pipeline,
          );
          expect(logical, isNotNull, reason: 'agent:capabilities payload must decode as a map');
          final capabilities = ProtocolCapabilities.fromJson(logical!);
          final agentActions = capabilities.extensions['agentActions'];
          expect(agentActions, isNotNull, reason: 'Hub capabilities must include extensions.agentActions');
          expect(agentActions, isA<Map<String, dynamic>>());
          final agentActionsMap = agentActions! as Map<String, dynamic>;
          expect(agentActionsMap['enabled'], isTrue);
          expect(agentActionsMap['supportsContext'], isFalse);
          expect(agentActionsMap['requiresIdempotencyKey'], isTrue);
          expect(agentActionsMap['methods'], isA<List<dynamic>>());
          expect(
            (agentActionsMap['methods'] as List<dynamic>).cast<String>(),
            contains(AgentActionRpcConstants.agentActionRunRpcMethodName),
          );
          expect(agentActionsMap['limits'], isA<Map<String, dynamic>>());
          expect(agentActionsMap['batchPolicy'], isA<Map<String, dynamic>>());
          expect(agentActionsMap, contains('elevatedAllowed'));
          expect(agentActionsMap, contains('supportsElevated'));
          expect(agentActionsMap['elevatedAllowed'], isA<bool>());
          expect(agentActionsMap['supportsElevated'], isA<bool>());
        } finally {
          session.socket.dispose();
        }
      },
      skip:
          readinessSkip ??
          (!E2EEnv.e2eHubExpectAgentActionsCapability
              ? 'Set E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY=true when the hub should advertise agentActions in capabilities.'
              : null),
      tags: const ['live'],
    );

    test(
      'should receive agent.action.* rpc:request after agent:ready when hub emits (E2E_HUB_EXPECT_AGENT_ACTION_RPC)',
      () async {
        final hubUrl = E2EEnv.e2eHubUrl!;
        final hubToken = E2EEnv.e2eHubToken!;
        final keyId = E2EEnv.e2ePayloadSigningKeyId!;
        final key = E2EEnv.e2ePayloadSigningKey!;

        final session = await _openSessionAfterSignedCapabilities(
          hubUrl: hubUrl,
          hubToken: hubToken,
          keyId: keyId,
          key: key,
        );
        final firstAgentActionRpc = Completer<RpcRequest>();
        try {
          session.socket.on('rpc:request', (dynamic data) {
            if (firstAgentActionRpc.isCompleted) {
              return;
            }
            unawaited(() async {
              final req = await _tryDecodeRpcRequestFromWire(data);
              if (req != null && req.method.startsWith('agent.action.')) {
                firstAgentActionRpc.complete(req);
              }
            }());
          });

          await _emitSignedAgentReady(
            socket: session.socket,
            signer: session.signer,
            pipeline: session.pipeline,
          );

          final rpc = await firstAgentActionRpc.future.timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw TimeoutException(
                'No inbound agent.action.* rpc:request within 25s after agent:ready '
                '(hub must emit test traffic when E2E_HUB_EXPECT_AGENT_ACTION_RPC=true).',
              );
            },
          );
          expect(rpc.method, startsWith('agent.action.'));
        } finally {
          session.socket.dispose();
        }
      },
      skip:
          readinessSkip ??
          (!E2EEnv.e2eHubExpectAgentActionRpc
              ? 'Set E2E_HUB_EXPECT_AGENT_ACTION_RPC=true when the hub is configured to send agent.action.* after ready.'
              : null),
      tags: const ['live'],
    );
  });
}
