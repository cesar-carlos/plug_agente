import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_views.dart';

void main() {
  final sample = UpdateCheckDiagnostics(
    checkedAt: DateTime.utc(2026, 5, 29, 12),
    configuredFeedUrl: 'https://example.com/appcast.xml',
    requestedFeedUrl: 'https://example.com/appcast.xml?cb=123',
    checkId: 'check-1',
    currentVersion: '1.0.0',
    probeRequestUrl: 'https://example.com/appcast.xml?cb=123',
    triggerStartedAt: DateTime.utc(2026, 5, 29, 12, 0, 1),
    triggerCompletedAt: DateTime.utc(2026, 5, 29, 12, 0, 2),
    completedAt: DateTime.utc(2026, 5, 29, 12, 0, 3),
    completionSource: UpdateCheckCompletionSource.updateAvailable,
    probeSucceeded: true,
    appcastProbeVersion: '2.0.0',
    appcastProbeOs: 'windows',
    appcastProbeItemCount: 1,
    probeMatchesSparkle: true,
    updateAvailable: true,
    remoteVersion: '2.0.0',
    remoteDisplayVersion: '2.0.0',
    assetUrl: 'https://example.com/PlugAgente-Setup-2.0.0.exe',
    assetSize: 1024,
    assetName: 'PlugAgente-Setup-2.0.0.exe',
    sha256: 'a' * 64,
    actualSha256: 'a' * 64,
    hashValidationStatus: 'valid',
    releaseNotes: 'Bug fixes',
    releaseNotesUrl: 'https://example.com/notes',
    installerPath: r'C:\PlugAgente\updates\setup.exe',
    installerLogPath: r'C:\PlugAgente\updates\setup.log',
    installDirectory: r'C:\PlugAgente',
    silentUpdateStrategy: 'currentUserThenElevated',
    launcherPath: r'C:\PlugAgente\updates\helper.exe',
    launcherStatusPath: r'C:\PlugAgente\updates\helper.status.json',
    launcherState: 'elevatedStarted',
    nonAdminExitCode: 5,
    nonAdminDurationMs: 1200,
    elevatedExitCode: 0,
    elevatedDurationMs: 300,
    elevatedRetryStarted: true,
    waitForAppExitDurationMs: 45,
    appPid: 1234,
    signatureStatus: 'valid',
    signatureRequired: true,
    updateDirectorySecurityStatus: 'restricted',
    installDirectoryWritable: true,
    elevatedCancelled: false,
    helperSha256: 'b' * 64,
    helperSignatureStatus: 'valid',
    feedSignatureStatus: 'valid',
    feedSignatureRequired: true,
    rolloutChannel: 'stable',
    rolloutPercentage: 100,
    rolloutBucket: 17,
    rolloutEligible: true,
    automaticFailureCount: 2,
    automaticCooldownUntil: DateTime.utc(2026, 5, 29, 18),
  );

  group('UpdateCheckDiagnostics typed views', () {
    test('context view exposes invocation metadata', () {
      final view = sample.context;
      expect(view.checkedAt, sample.checkedAt);
      expect(view.checkId, 'check-1');
      expect(view.currentVersion, '1.0.0');
    });

    test('timing view computes trigger duration', () {
      final view = sample.timing;
      expect(view.completionSource, UpdateCheckCompletionSource.updateAvailable);
      expect(view.triggerDuration, const Duration(seconds: 1));
    });

    test('probe view forwards appcast-derived fields', () {
      final view = sample.probe;
      expect(view.succeeded, isTrue);
      expect(view.version, '2.0.0');
      expect(view.os, 'windows');
      expect(view.matchesSparkle, isTrue);
    });

    test('asset view groups remote/asset metadata', () {
      final view = sample.asset;
      expect(view.assetSize, 1024);
      expect(view.expectedSha256, 'a' * 64);
      expect(view.actualSha256, 'a' * 64);
      expect(view.releaseNotesUrl, 'https://example.com/notes');
    });

    test('launcher view groups elevation/installer state', () {
      final view = sample.launcher;
      expect(view.launcherState, 'elevatedStarted');
      expect(view.elevatedRetryStarted, isTrue);
      expect(view.elevatedCancelled, isFalse);
      expect(view.installDirectoryWritable, isTrue);
    });

    test('signature view groups helper + feed Ed25519 status', () {
      final view = sample.signature;
      expect(view.helperSignatureStatus, 'valid');
      expect(view.feedSignatureStatus, 'valid');
      expect(view.signatureRequired, isTrue);
    });

    test('rollout view groups channel + bucket', () {
      final view = sample.rollout;
      expect(view.channel, 'stable');
      expect(view.percentage, 100);
      expect(view.bucket, 17);
      expect(view.eligible, isTrue);
    });

    test('cooldown view groups breaker counters', () {
      final view = sample.cooldown;
      expect(view.failureCount, 2);
      expect(view.cooldownUntil, DateTime.utc(2026, 5, 29, 18));
    });

    test('errors view reports hasAnyError correctly', () {
      expect(sample.errors.hasAnyError, isFalse);

      final withError = sample.copyWith(errorMessage: 'boom');
      expect(withError.errors.hasAnyError, isTrue);
      expect(withError.errors.errorMessage, 'boom');
    });
  });
}
