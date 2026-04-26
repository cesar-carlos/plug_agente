import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';

import '../helpers/e2e_env.dart';

/// WebSocket + Socket.IO connect smoke against a real hub (opt-in).
///
/// Uses the same [SocketDataSource] and URL normalization as the app transport.
void main() async {
  await E2EEnv.load();

  final run = E2EEnv.runLiveHubTests;
  final urlOrNull = E2EEnv.e2eHubUrl;
  final tokenOrNull = E2EEnv.e2eHubToken;

  final skipMessage = !run
      ? 'Set RUN_LIVE_HUB_TESTS=true in .env to run hub Socket live tests.'
      : (urlOrNull == null || urlOrNull.isEmpty)
      ? 'Set E2E_HUB_URL (hub base URL, e.g. https://host:port or wss://host/path).'
      : (tokenOrNull == null || tokenOrNull.isEmpty)
      ? 'Set E2E_HUB_TOKEN (agent token for the Socket.IO auth handshake).'
      : null;

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
    );
  });
}
