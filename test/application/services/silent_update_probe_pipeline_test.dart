import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/application/services/silent_update_probe_pipeline.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

import '../../helpers/auto_update_test_fakes.dart';

void main() {
  group('SilentUpdateProbePipeline', () {
    late FakeAppcastProbeService probe;
    late FakeAppcastSignatureVerifier signatureVerifier;
    late FakePendingSilentUpdateStore pendingStore;
    late PersistentCircuitBreaker breaker;
    late SilentUpdateProbePipeline pipeline;
    UpdateCheckDiagnostics? latestDiagnostics;
    var persistCount = 0;

    SilentUpdateProbePipelineRequest request({
      bool userInitiated = false,
      bool Function()? cancelRequested,
      int rolloutBucket = 0,
    }) {
      return SilentUpdateProbePipelineRequest(
        feedUrl: 'https://example.com/appcast.xml',
        checkId: 'check-1',
        userInitiated: userInitiated,
        cancelRequested: cancelRequested ?? () => false,
        rolloutBucket: rolloutBucket,
        diagnostics: UpdateCheckDiagnostics(
          checkedAt: DateTime.utc(2026, 6, 10, 12),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          checkId: 'check-1',
          currentVersion: AppConstants.appVersion,
        ),
        onDiagnosticsUpdated: (diagnostics) => latestDiagnostics = diagnostics,
        persistDiagnostics: () async {
          persistCount++;
        },
      );
    }

    setUp(() {
      dotenv.clean();
      dotenv.loadFromString(
        envString:
            'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
            'AUTO_UPDATE_CHANNEL=stable\n'
            'AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=false',
      );
      probe = FakeAppcastProbeService();
      signatureVerifier = FakeAppcastSignatureVerifier();
      pendingStore = FakePendingSilentUpdateStore();
      breaker = PersistentCircuitBreaker(
        persistence: InMemoryCircuitBreakerPersistence(),
        threshold: 3,
        cooldown: const Duration(minutes: 5),
        logName: 'silent_update_probe_pipeline_test',
        clock: () => DateTime.utc(2026, 6, 10, 12),
      );
      pipeline = SilentUpdateProbePipeline(
        appcastProbeService: probe,
        signatureVerifier: signatureVerifier,
        pendingStore: pendingStore,
        automaticFailureBreaker: breaker,
        clock: () => DateTime.utc(2026, 6, 10, 12),
      );
      latestDiagnostics = null;
      persistCount = 0;
    });

    test('returns validation failure when appcast is missing sha256', () async {
      probe.result = const AppcastProbeResult(
        requestUrl: 'https://example.com/appcast.xml',
        latestVersion: '99.0.0+1',
        assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
        assetSize: 5,
        assetName: 'PlugAgente-Setup-99.0.0.exe',
        itemCount: 1,
      );

      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      expect(terminal.outcome.isError(), isTrue);
      terminal.outcome.fold(
        (_) => fail('Expected failure'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
          expect((failure as domain.Failure).context['validation_code'], 'invalid_sha256');
        },
      );
      expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticValidationFailure);
      expect(latestDiagnostics?.validationErrorCode, 'invalid_sha256');
      expect(persistCount, greaterThan(0));
    });

    test('returns validation failure for disallowed HTTP installer URL', () async {
      probe.result = const AppcastProbeResult(
        requestUrl: 'https://example.com/appcast.xml',
        latestVersion: '99.0.0+1',
        assetUrl: 'http://updates.example.com/PlugAgente-Setup-99.0.0.exe',
        assetSize: 5,
        assetName: 'PlugAgente-Setup-99.0.0.exe',
        sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
        itemCount: 1,
      );

      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      expect(latestDiagnostics?.validationErrorCode, 'invalid_asset_url');
      terminal.outcome.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });

    test('returns rolloutSkipped when channel does not match configured channel', () async {
      probe.result = const AppcastProbeResult(
        requestUrl: 'https://example.com/appcast.xml',
        latestVersion: '99.0.0+1',
        assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
        assetSize: 5,
        assetName: 'PlugAgente-Setup-99.0.0.exe',
        sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
        channel: 'beta',
        rolloutPercentage: 100,
        itemCount: 1,
      );

      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      terminal.outcome.fold(
        (outcome) => expect(outcome, SilentUpdateOutcome.rolloutSkipped),
        (_) => fail('Expected success'),
      );
      expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticRolloutSkipped);
      expect(latestDiagnostics?.rolloutEligible, isFalse);
    });

    test('returns rolloutSkipped when rollout bucket is outside percentage', () async {
      probe.result = const AppcastProbeResult(
        requestUrl: 'https://example.com/appcast.xml',
        latestVersion: '99.0.0+1',
        assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
        assetSize: 5,
        assetName: 'PlugAgente-Setup-99.0.0.exe',
        sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
        channel: 'stable',
        rolloutPercentage: 25,
        itemCount: 1,
      );

      final result = await pipeline.run(request(rolloutBucket: 50));

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      terminal.outcome.fold(
        (outcome) => expect(outcome, SilentUpdateOutcome.rolloutSkipped),
        (_) => fail('Expected success'),
      );
      expect(latestDiagnostics?.rolloutBucket, 50);
      expect(latestDiagnostics?.rolloutPercentage, 25);
    });

    test('proceeds to download (UAC gate removed from probe; elevation happens at apply)', () async {
      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeProceedToDownload>());
      expect(pendingStore.writeCount, 1);
      expect(latestDiagnostics?.updateAvailable, isTrue);
      expect(latestDiagnostics?.pendingVersion, '99.0.0+1');
    });

    test('userInitiated proceeds to download', () async {
      final result = await pipeline.run(request(userInitiated: true));

      expect(result, isA<SilentUpdateProbeProceedToDownload>());
      expect(pendingStore.writeCount, 1);
      expect(pendingStore.pending, isA<PendingSilentUpdateProbed>());
    });

    test('returns cancelled when cancel is requested after pending write', () async {
      final result = await pipeline.run(
        request(cancelRequested: () => true),
      );

      expect(result, isA<SilentUpdateProbeCancelled>());
      expect(pendingStore.writeCount, 1);
      expect(latestDiagnostics?.updateAvailable, isTrue);
    });

    test('returns network failure when probe reports an error', () async {
      probe.result = const AppcastProbeResult(
        requestUrl: 'https://example.com/appcast.xml',
        errorMessage: 'HTTP 503',
      );

      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticDownloadFailure);
      terminal.outcome.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.NetworkFailure>()),
      );
    });

    test('returns noNewVersion when remote version is not newer', () async {
      probe.result = const AppcastProbeResult(
        requestUrl: 'https://example.com/appcast.xml',
        latestVersion: AppConstants.appVersion,
        assetUrl: 'https://example.com/PlugAgente-Setup-current.exe',
        assetSize: 5,
        assetName: 'PlugAgente-Setup-current.exe',
        sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
        channel: 'stable',
        rolloutPercentage: 100,
        itemCount: 1,
      );

      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      terminal.outcome.fold(
        (outcome) => expect(outcome, SilentUpdateOutcome.noNewVersion),
        (_) => fail('Expected success'),
      );
      expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticUpdateNotAvailable);
    });

    test('proceeds to download when probe and validation succeed', () async {
      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeProceedToDownload>());
      final proceed = result as SilentUpdateProbeProceedToDownload;
      expect(proceed.remoteVersion, '99.0.0+1');
      expect(pendingStore.writeCount, 1);
      expect(latestDiagnostics?.updateAvailable, isTrue);
    });

    test('rejects feed when signature is required but invalid', () async {
      dotenv.clean();
      dotenv.loadFromString(
        envString:
            'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
            'AUTO_UPDATE_CHANNEL=stable\n'
            'AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true\n'
            'AUTO_UPDATE_FEED_PUBLIC_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );
      signatureVerifier.status = AppcastSignatureVerificationStatus.invalid;

      final result = await pipeline.run(request());

      expect(result, isA<SilentUpdateProbeTerminal>());
      final terminal = result as SilentUpdateProbeTerminal;
      expect(latestDiagnostics?.validationErrorCode, 'feed_signature_invalid');
      terminal.outcome.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });
  });
}
