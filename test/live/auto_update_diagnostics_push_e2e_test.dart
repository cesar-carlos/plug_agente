@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/infrastructure/external_services/throttled_auto_update_diagnostics_gateway.dart';

import '../helpers/e2e_env.dart';

/// End-to-end smoke for the `agent.autoUpdate.diagnostics.push` method
/// (Fase 7 of the auto-update evolution plan). This test is gated by
/// `RUN_LIVE_HUB_TESTS=true` because it requires a running Plug hub at
/// `E2E_HUB_URL` (with `E2E_HUB_TOKEN` for auth) that implements the
/// new RPC method.
///
/// Goals:
/// - confirm the wire payload matches the schema published in
///   `docs/communication/schemas/auto_update_diagnostics.schema.json`;
/// - confirm the hub accepts the notification without error;
/// - confirm the throttle window holds across two adjacent pushes.
///
/// To run locally:
///   $env:RUN_LIVE_HUB_TESTS = 'true'
///   $env:E2E_HUB_URL = 'http://localhost:3000'
///   $env:E2E_HUB_TOKEN = '`<token>`'
///   flutter test test/live/auto_update_diagnostics_push_e2e_test.dart --tags live
void main() {
  late bool liveEnabled;
  late String hubUrl;
  late String hubToken;

  setUpAll(() async {
    await E2EEnv.load();
    liveEnabled = (Platform.environment['RUN_LIVE_HUB_TESTS'] ?? '').toLowerCase() == 'true';
    hubUrl = Platform.environment['E2E_HUB_URL'] ?? '';
    hubToken = Platform.environment['E2E_HUB_TOKEN'] ?? '';
  });

  test(
    'pushes diagnostics to the hub and respects the throttle window',
    () async {
      if (!liveEnabled) {
        markTestSkipped('RUN_LIVE_HUB_TESTS != true; live hub test disabled');
        return;
      }
      if (hubUrl.isEmpty || hubToken.isEmpty) {
        fail(
          'Live test enabled but E2E_HUB_URL/E2E_HUB_TOKEN are missing. '
          'See docs/testing/e2e_setup.md for the required environment.',
        );
      }

      // Real implementations live in the application's DI; for this smoke
      // test we exercise the throttled gateway directly with a thin
      // transport that signals success when the hub returns 200/204.
      var sendCount = 0;
      final gateway = ThrottledAutoUpdateDiagnosticsGateway(
        agentId: 'live-e2e-test',
        transport: (payload) async {
          sendCount++;
          // The hub side is expected to validate against the schema and
          // return a 2xx for valid payloads. We use a plain HTTP request
          // here because the Socket.IO client is exercised elsewhere; this
          // smoke only confirms that the wire shape is accepted.
          final client = HttpClient();
          try {
            final request = await client.postUrl(Uri.parse('$hubUrl/agent/autoUpdate/diagnostics/push'));
            request.headers.set('Authorization', 'Bearer $hubToken');
            request.headers.contentType = ContentType.json;
            request.write(payload.toString());
            final response = await request.close();
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException('Hub returned ${response.statusCode}');
            }
            await response.drain<void>();
          } finally {
            client.close(force: true);
          }
        },
      );

      final diagnostics = UpdateCheckDiagnostics(
        checkedAt: DateTime.now().toUtc(),
        configuredFeedUrl: 'https://cesar-carlos.github.io/plug_agente/appcast.xml',
        requestedFeedUrl: 'https://cesar-carlos.github.io/plug_agente/appcast.xml',
        checkId: 'live-e2e-${DateTime.now().millisecondsSinceEpoch}',
        currentVersion: '1.6.8+1',
        completionSource: UpdateCheckCompletionSource.updateNotAvailable,
        updateAvailable: false,
      );

      await gateway.push(
        diagnostics: diagnostics,
        source: AutoUpdateDiagnosticsSource.manual,
      );
      // Second push should be silently dropped by the throttle.
      await gateway.push(
        diagnostics: diagnostics,
        source: AutoUpdateDiagnosticsSource.manual,
      );

      expect(sendCount, 1, reason: 'throttle must keep the second push from leaving the client');
      expect(gateway.lastPushAt, isNotNull, reason: 'first push must record the timestamp');
    },
    timeout: const Timeout(Duration(seconds: 30)),
    tags: <String>['live'],
  );
}
