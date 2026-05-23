import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

import '../helpers/e2e_env.dart';

/// WebSocket + Socket.IO connect smoke against a real hub (opt-in).
///
/// Uses the same [SocketDataSource] and URL normalization as the app transport.
void main() async {
  await E2EEnv.load();

  final run = E2EEnv.runLiveHubTests;
  final urlOrNull = E2EEnv.e2eHubUrl;
  final tokenOrNull = E2EEnv.e2eHubToken;

  var skipMessage = !run
      ? 'Set RUN_LIVE_HUB_TESTS=true in .env to run hub Socket live tests.'
      : (urlOrNull == null || urlOrNull.isEmpty)
      ? 'Set E2E_HUB_URL (hub base URL, e.g. https://host:port or wss://host/path).'
      : (tokenOrNull == null || tokenOrNull.isEmpty)
      ? 'Set E2E_HUB_TOKEN (agent token for the Socket.IO auth handshake).'
      : null;

  var signingSkipMessage = !E2EEnv.runLiveHubSigningTests
      ? 'Set RUN_LIVE_HUB_SIGNING_TESTS=true in .env to run signed PayloadFrame hub tests.'
      : (urlOrNull == null || urlOrNull.isEmpty)
      ? 'Set E2E_HUB_URL (hub base URL, e.g. https://host:port or wss://host/path).'
      : (tokenOrNull == null || tokenOrNull.isEmpty)
      ? 'Set E2E_HUB_TOKEN (agent token for the Socket.IO auth handshake).'
      : (E2EEnv.e2ePayloadSigningKeyId == null || E2EEnv.e2ePayloadSigningKey == null)
      ? 'Set PAYLOAD_SIGNING_KEY_ID/PAYLOAD_SIGNING_KEY or PAYLOAD_SIGNING_ACTIVE_KEY_ID/PAYLOAD_SIGNING_KEY.'
      : null;
  skipMessage ??= E2EEnv.liveHubBlockingPreflightFailureMessage();

  signingSkipMessage ??= E2EEnv.liveHubBlockingPreflightFailureMessage(requireSigning: true);

  group('Hub Socket.IO (live E2E)', () {
    test(
      'should connect to agents namespace then disconnect',
      () async {
        final hubUrl = E2EEnv.e2eHubUrl;
        final hubToken = E2EEnv.e2eHubToken;
        if (hubUrl == null || hubUrl.isEmpty || hubToken == null || hubToken.isEmpty) {
          fail('E2E_HUB_URL and E2E_HUB_TOKEN must be set when this test is not skipped');
        }
final ds = SocketDataSource();
        final socket = ds.createSocket(hubUrl, authToken: hubToken);
        final completer = Completer<void>();

        socket
          ..on('connect', (_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          })
          ..on('connect_error', (dynamic data) {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('connect_error from hub (check URL, token, and network)'),
              );
            }
          });

        socket.connect();
        try {
          await completer.future.timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw TimeoutException('Socket.IO connect not received within 25s');
            },
          );
          expect(socket.connected, isTrue);
        } finally {
          socket.dispose();
        }
      },
      skip: skipMessage,
      tags: const ['live'],
    );

    test(
      'should complete signed PayloadFrame capabilities handshake',
      () async {
        final hubUrl = E2EEnv.e2eHubUrl;
        final hubToken = E2EEnv.e2eHubToken;
        final keyId = E2EEnv.e2ePayloadSigningKeyId;
        final key = E2EEnv.e2ePayloadSigningKey;
        if (hubUrl == null ||
            hubUrl.isEmpty ||
            hubToken == null ||
            hubToken.isEmpty ||
            keyId == null ||
            keyId.isEmpty ||
            key == null ||
            key.isEmpty) {
          fail('E2E hub URL, token, and signing key env vars must be set when this test is not skipped');
        }
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
        final unsignedFrame = (await pipeline.prepareSendAsync(
          registerPayload,
          metricEventName: 'agent:register',
        )).getOrThrow();
        final signedFrame = unsignedFrame.copyWith(
          signature: signer.signFrame(unsignedFrame).toJson(),
        );

        final ds = SocketDataSource();
        final socket = ds.createSocket(hubUrl, authToken: hubToken);
        final connected = Completer<void>();
        final capabilities = Completer<PayloadFrame>();
        var registerSent = false;

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
          ..on('agent:register_error', (dynamic data) {
            if (capabilities.isCompleted) {
              return;
            }
            capabilities.completeError(
              StateError('agent:register_error from hub after signed register: $data'),
            );
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
          })
          ..on('disconnect', (dynamic reason) {
            if (!registerSent || capabilities.isCompleted) {
              return;
            }
            capabilities.completeError(
              StateError(
                'socket disconnected before agent:capabilities after signed register: $reason',
              ),
            );
          });

        socket.connect();
        try {
          await connected.future.timeout(const Duration(seconds: 25));
          registerSent = true;
          socket.emit('agent:register', signedFrame.toJson());
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
        } finally {
          socket.dispose();
        }
      },
      skip: signingSkipMessage,
      tags: const ['live'],
    );
  });
}
