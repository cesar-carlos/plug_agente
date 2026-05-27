import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/throttled_auto_update_diagnostics_gateway.dart';

void main() {
  group('ThrottledAutoUpdateDiagnosticsGateway', () {
    UpdateCheckDiagnostics buildDiagnostics({String checkId = 'id-x'}) {
      return UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026, 5, 26, 12),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml',
        checkId: checkId,
        currentVersion: '1.6.8+1',
        completionSource: UpdateCheckCompletionSource.updateAvailable,
        updateAvailable: true,
        remoteVersion: '1.7.0+1',
        helperSignatureStatus: 'valid',
        feedSignatureStatus: 'valid',
        feedSignatureRequired: true,
      );
    }

    test('sends the first call through and records the timestamp', () async {
      var calls = 0;
      Map<String, dynamic>? lastPayload;
      final fakeNow = DateTime.utc(2026, 5, 26, 12);
      final gateway = ThrottledAutoUpdateDiagnosticsGateway(
        agentId: 'agent-42',
        clock: () => fakeNow,
        transport: (payload) async {
          calls++;
          lastPayload = payload;
        },
      );

      await gateway.push(
        diagnostics: buildDiagnostics(checkId: 'id-1'),
        source: AutoUpdateDiagnosticsSource.manual,
      );

      expect(calls, 1);
      expect(gateway.lastPushAt, fakeNow);
      expect(lastPayload?['agentId'], 'agent-42');
      expect(lastPayload?['source'], 'manual');
      expect(lastPayload?['appVersion'], '1.6.8+1');
      expect(lastPayload?['checkId'], 'id-1');
      expect(lastPayload?['feedSignatureStatus'], 'valid');
    });

    test('drops follow-up calls within the throttle window', () async {
      var calls = 0;
      var fakeNow = DateTime.utc(2026, 5, 26, 12);
      final gateway = ThrottledAutoUpdateDiagnosticsGateway(
        agentId: 'agent-42',
        clock: () => fakeNow,
        transport: (_) async {
          calls++;
        },
      );

      await gateway.push(
        diagnostics: buildDiagnostics(),
        source: AutoUpdateDiagnosticsSource.silent,
      );
      // Advance 30 seconds: still within the 60s window.
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      await gateway.push(
        diagnostics: buildDiagnostics(checkId: 'id-2'),
        source: AutoUpdateDiagnosticsSource.silent,
      );

      expect(calls, 1, reason: 'throttle must drop the second call');
    });

    test('allows another call after the window elapses', () async {
      var calls = 0;
      var fakeNow = DateTime.utc(2026, 5, 26, 12);
      final gateway = ThrottledAutoUpdateDiagnosticsGateway(
        agentId: 'agent-42',
        clock: () => fakeNow,
        transport: (_) async {
          calls++;
        },
      );

      await gateway.push(
        diagnostics: buildDiagnostics(),
        source: AutoUpdateDiagnosticsSource.background,
      );
      fakeNow = fakeNow.add(const Duration(seconds: 61));
      await gateway.push(
        diagnostics: buildDiagnostics(checkId: 'id-2'),
        source: AutoUpdateDiagnosticsSource.background,
      );

      expect(calls, 2);
    });

    test('does not propagate transport failures', () async {
      final fakeNow = DateTime.utc(2026, 5, 26, 12);
      final gateway = ThrottledAutoUpdateDiagnosticsGateway(
        agentId: 'agent-42',
        clock: () => fakeNow,
        transport: (_) async {
          throw Exception('hub down');
        },
      );

      // Must not throw — telemetry is best-effort.
      await gateway.push(
        diagnostics: buildDiagnostics(),
        source: AutoUpdateDiagnosticsSource.manual,
      );
      expect(gateway.lastPushAt, isNull, reason: 'failures must not advance the throttle window');
    });

    test('omits sensitive paths and truncates long error messages', () async {
      final longError = 'x' * 2000;
      Map<String, dynamic>? payload;
      final gateway = ThrottledAutoUpdateDiagnosticsGateway(
        agentId: 'agent-42',
        clock: () => DateTime.utc(2026, 5, 26, 12),
        transport: (received) async {
          payload = received;
        },
      );

      await gateway.push(
        diagnostics: UpdateCheckDiagnostics(
          checkedAt: DateTime.utc(2026, 5, 26, 12),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          currentVersion: '1.6.8+1',
          // Sensitive fields below MUST NOT appear in the payload.
          installerPath: r'C:\secret\PlugAgente-Setup.exe',
          launcherPath: r'C:\secret\plug_update_launcher.exe',
          installerLogPath: r'C:\secret\install.log',
          launcherStatusPath: r'C:\secret\status.json',
          installDirectory: r'C:\Program Files\Plug',
          actualSha256: 'a' * 64,
          errorMessage: longError,
        ),
        source: AutoUpdateDiagnosticsSource.manual,
      );

      expect(payload, isNotNull);
      final keys = payload!.keys.toSet();
      expect(keys.contains('installerPath'), isFalse);
      expect(keys.contains('launcherPath'), isFalse);
      expect(keys.contains('installerLogPath'), isFalse);
      expect(keys.contains('launcherStatusPath'), isFalse);
      expect(keys.contains('installDirectory'), isFalse);
      expect(keys.contains('actualSha256'), isFalse);
      expect(payload!['errorMessage'], hasLength(1024));
    });
  });
}
