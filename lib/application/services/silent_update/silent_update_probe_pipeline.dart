import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

sealed class SilentUpdateProbePipelineResult {
  const SilentUpdateProbePipelineResult();
}

final class SilentUpdateProbeProceedToDownload extends SilentUpdateProbePipelineResult {
  SilentUpdateProbeProceedToDownload({
    required this.probeResult,
    required this.remoteVersion,
    required this.diagnostics,
  });

  final AppcastProbeResult probeResult;
  final String remoteVersion;
  final UpdateCheckDiagnostics diagnostics;
}

final class SilentUpdateProbeTerminal extends SilentUpdateProbePipelineResult {
  SilentUpdateProbeTerminal({
    required this.outcome,
    required this.diagnostics,
    this.notifyDiagnostics = false,
  });

  final Result<SilentUpdateOutcome> outcome;
  final UpdateCheckDiagnostics diagnostics;
  final bool notifyDiagnostics;
}

final class SilentUpdateProbeCancelled extends SilentUpdateProbePipelineResult {
  SilentUpdateProbeCancelled({required this.diagnostics});

  final UpdateCheckDiagnostics diagnostics;
}

class SilentUpdateProbePipelineRequest {
  const SilentUpdateProbePipelineRequest({
    required this.feedUrl,
    required this.checkId,
    required this.userInitiated,
    required this.cancelRequested,
    required this.rolloutBucket,
    required this.diagnostics,
    required this.onDiagnosticsUpdated,
    required this.persistDiagnostics,
  });

  final String feedUrl;
  final String? checkId;
  final bool userInitiated;
  final bool Function() cancelRequested;
  final int rolloutBucket;
  final UpdateCheckDiagnostics diagnostics;
  final void Function(UpdateCheckDiagnostics) onDiagnosticsUpdated;
  final Future<void> Function() persistDiagnostics;
}

/// Probe → validate → download-decision pipeline extracted from the silent
/// update coordinator so it can delegate the pre-download phase without
/// duplicating rules.
class SilentUpdateProbePipeline {
  SilentUpdateProbePipeline({
    required IAppcastProbeService appcastProbeService,
    required IAppcastSignatureVerifier signatureVerifier,
    required IUacDetector uacDetector,
    required IPendingSilentUpdateStore pendingStore,
    required PersistentCircuitBreaker automaticFailureBreaker,
    IAutoUpdateMetricsCollector? metricsCollector,
    DateTime Function()? clock,
  }) : _appcastProbeService = appcastProbeService,
       _signatureVerifier = signatureVerifier,
       _uacDetector = uacDetector,
       _pendingStore = pendingStore,
       _automaticFailureBreaker = automaticFailureBreaker,
       _metricsCollector = metricsCollector,
       _clock = clock ?? DateTime.now;

  final IAppcastProbeService _appcastProbeService;
  final IAppcastSignatureVerifier _signatureVerifier;
  final IUacDetector _uacDetector;
  final IPendingSilentUpdateStore _pendingStore;
  final PersistentCircuitBreaker _automaticFailureBreaker;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final DateTime Function() _clock;

  Future<SilentUpdateProbePipelineResult> run(SilentUpdateProbePipelineRequest request) async {
    var diagnostics = request.diagnostics;

    Future<void> publish(UpdateCheckDiagnostics next) async {
      diagnostics = next;
      request.onDiagnosticsUpdated(next);
      await request.persistDiagnostics();
    }

    final probeStart = _clock();
    final probeResult = await _appcastProbeService.probeLatest(feedUrl: request.feedUrl);
    _metricsCollector?.recordAutoUpdateProbeDuration(_clock().difference(probeStart));
    await publish(
      diagnostics.copyWith(
        probeRequestUrl: probeResult.requestUrl,
        probeSucceeded: probeResult.errorMessage == null,
        appcastProbeVersion: probeResult.latestVersion,
        appcastProbeOs: probeResult.os,
        appcastProbeItemCount: probeResult.itemCount,
        remoteVersion: probeResult.latestVersion,
        remoteDisplayVersion: probeResult.latestVersion,
        assetUrl: probeResult.assetUrl,
        releaseNotes: probeResult.releaseNotes,
        releaseNotesUrl: probeResult.releaseNotesUrl,
        assetSize: probeResult.assetSize,
        assetName: probeResult.assetName,
        sha256: probeResult.sha256,
        rolloutChannel: probeResult.channel ?? defaultAutoUpdateChannel,
        rolloutPercentage: probeResult.rolloutPercentage ?? 100,
        rolloutBucket: request.rolloutBucket,
        probeErrorMessage: probeResult.errorMessage,
      ),
    );

    if (probeResult.errorMessage != null) {
      final now = _clock();
      final failureState = await _automaticFailureBreaker.recordFailure();
      await publish(
        diagnostics.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          errorMessage: probeResult.errorMessage,
        ),
      );
      return SilentUpdateProbeTerminal(
        diagnostics: diagnostics,
        outcome: Failure<SilentUpdateOutcome, Exception>(
          domain.NetworkFailure.withContext(
            message: 'Silent update appcast probe failed',
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': request.feedUrl,
              'probe_error': probeResult.errorMessage,
            },
          ),
        ),
      );
    }

    final validationError = _validateSilentProbeResult(probeResult);
    if (validationError != null) {
      final now = _clock();
      final failureState = await _automaticFailureBreaker.recordFailure();
      await publish(
        diagnostics.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          validationErrorCode: validationError.code,
          errorMessage: validationError.message,
        ),
      );
      return SilentUpdateProbeTerminal(
        diagnostics: diagnostics,
        outcome: Failure<SilentUpdateOutcome, Exception>(
          domain.ValidationFailure.withContext(
            message: validationError.message,
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': request.feedUrl,
              'validation_code': validationError.code,
            },
          ),
        ),
      );
    }

    final environment = AppEnvironment.snapshot();
    final feedSignatureRequired = resolveAutoUpdateRequireFeedSignature(environment: environment);
    final feedPublicKey = resolveAutoUpdateFeedPublicKey(environment: environment);
    final signatureStatus = await _signatureVerifier.verifyEnclosure(
      canonicalPayload: buildAppcastEnclosureSignable(
        version: probeResult.latestVersion!,
        os: probeResult.os ?? '',
        sha256: probeResult.sha256!,
        channel: probeResult.channel ?? defaultAutoUpdateChannel,
        rolloutPercentage: probeResult.rolloutPercentage ?? 100,
        assetUrl: probeResult.assetUrl!,
        assetSize: probeResult.assetSize!,
      ),
      base64Signature: probeResult.edSignature,
      base64PublicKey: feedPublicKey,
    );
    await publish(
      diagnostics.copyWith(
        feedSignatureStatus: signatureStatus.name,
        feedSignatureRequired: feedSignatureRequired,
      ),
    );
    if (feedSignatureRequired && signatureStatus != AppcastSignatureVerificationStatus.valid) {
      final now = _clock();
      final failureState = await _automaticFailureBreaker.recordFailure();
      final code = 'feed_signature_${signatureStatus.name}';
      final message =
          'Silent update appcast signature is required but '
          '${signatureStatus.name} (operator must publish a signed item or '
          'set AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=false to bypass)';
      await publish(
        diagnostics.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          validationErrorCode: code,
          errorMessage: message,
        ),
      );
      return SilentUpdateProbeTerminal(
        diagnostics: diagnostics,
        outcome: Failure<SilentUpdateOutcome, Exception>(
          domain.ValidationFailure.withContext(
            message: message,
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': request.feedUrl,
              'validation_code': code,
              'signature_status': signatureStatus.name,
            },
          ),
        ),
      );
    }

    final remoteVersion = probeResult.latestVersion!;
    final rolloutEligible = _isProbeEligibleForConfiguredChannel(
      probeResult,
      rolloutBucket: request.rolloutBucket,
    );
    await publish(
      diagnostics.copyWith(
        rolloutEligible: rolloutEligible,
      ),
    );
    if (!rolloutEligible) {
      final now = _clock();
      await _automaticFailureBreaker.reset();
      await publish(
        diagnostics.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticRolloutSkipped,
          updateAvailable: false,
        ),
      );
      return SilentUpdateProbeTerminal(
        diagnostics: diagnostics,
        outcome: const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.rolloutSkipped),
      );
    }

    final isNewer = AppVersionComparator.isRemoteVersionNewer(
      remoteVersion: remoteVersion,
      currentVersion: AppConstants.appVersion,
    );
    if (!isNewer) {
      final now = _clock();
      await _automaticFailureBreaker.reset();
      await publish(
        diagnostics.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
          updateAvailable: false,
        ),
      );
      return SilentUpdateProbeTerminal(
        diagnostics: diagnostics,
        outcome: const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.noNewVersion),
      );
    }

    if (!request.userInitiated && _uacDetector.requiresUserConsentForElevation()) {
      final now = _clock();
      await _automaticFailureBreaker.reset();
      await publish(
        diagnostics.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
          updateAvailable: true,
          pendingVersion: remoteVersion,
        ),
      );
      _metricsCollector?.recordAutoUpdateAwaitingUserConsent();
      return SilentUpdateProbeTerminal(
        diagnostics: diagnostics,
        outcome: const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.requiresUserConsent),
        notifyDiagnostics: true,
      );
    }

    await _pendingStore.write(
      PendingSilentUpdateProbed(
        version: remoteVersion,
        startedAt: _clock(),
      ),
    );
    await publish(
      diagnostics.copyWith(
        updateAvailable: true,
        pendingVersion: remoteVersion,
        triggerStartedAt: _clock(),
      ),
    );

    if (request.cancelRequested()) {
      return SilentUpdateProbeCancelled(diagnostics: diagnostics);
    }

    return SilentUpdateProbeProceedToDownload(
      probeResult: probeResult,
      remoteVersion: remoteVersion,
      diagnostics: diagnostics,
    );
  }

  bool _isProbeEligibleForConfiguredChannel(
    AppcastProbeResult result, {
    required int rolloutBucket,
  }) {
    final configuredChannel = resolveAutoUpdateChannel(environment: AppEnvironment.snapshot());
    final remoteChannel = (result.channel == null || result.channel!.isEmpty)
        ? defaultAutoUpdateChannel
        : result.channel!.toLowerCase();
    if (remoteChannel != configuredChannel) return false;
    final rolloutPercentage = result.rolloutPercentage ?? 100;
    return rolloutPercentage >= 100 || rolloutBucket < rolloutPercentage;
  }

  _SilentProbeValidationError? _validateSilentProbeResult(AppcastProbeResult result) {
    for (final validator in _silentProbeValidators) {
      final error = validator(result);
      if (error != null) return error;
    }
    return null;
  }

  static final List<_SilentProbeValidationError? Function(AppcastProbeResult)> _silentProbeValidators = [
    _requireLatestVersion,
    _requireAssetUrl,
    _requireAllowedAssetUrl,
    _requireSupportedOs,
    _requireValidAssetSize,
    _requireValidAssetName,
    _requireValidSha256,
    _requireValidRolloutPercentage,
  ];
}

class _SilentProbeValidationError {
  const _SilentProbeValidationError({required this.code, required this.message});
  final String code;
  final String message;
}

_SilentProbeValidationError? _requireLatestVersion(AppcastProbeResult result) {
  final version = result.latestVersion?.trim();
  if (version == null || version.isEmpty) {
    return const _SilentProbeValidationError(
      code: 'missing_latest_version',
      message: 'Silent update appcast is missing the latest version',
    );
  }
  return null;
}

_SilentProbeValidationError? _requireAssetUrl(AppcastProbeResult result) {
  final assetUrl = result.assetUrl?.trim();
  if (assetUrl == null || assetUrl.isEmpty) {
    return const _SilentProbeValidationError(
      code: 'missing_asset_url',
      message: 'Silent update appcast is missing the installer URL',
    );
  }
  return null;
}

_SilentProbeValidationError? _requireAllowedAssetUrl(AppcastProbeResult result) {
  final assetUrl = result.assetUrl?.trim() ?? '';
  if (!isAutoUpdateInstallerUrl(assetUrl)) {
    return const _SilentProbeValidationError(
      code: 'invalid_asset_url',
      message: 'Silent update appcast has an invalid installer URL',
    );
  }
  return null;
}

_SilentProbeValidationError? _requireSupportedOs(AppcastProbeResult result) {
  final os = result.os?.trim().toLowerCase();
  if (os != null && os.isNotEmpty && os != 'windows') {
    return const _SilentProbeValidationError(
      code: 'unsupported_os',
      message: 'Silent update appcast targets an unsupported operating system',
    );
  }
  return null;
}

_SilentProbeValidationError? _requireValidAssetSize(AppcastProbeResult result) {
  final assetSize = result.assetSize;
  if (assetSize == null || assetSize <= 0) {
    return const _SilentProbeValidationError(
      code: 'invalid_asset_size',
      message: 'Silent update appcast is missing a valid installer size',
    );
  }
  return null;
}

_SilentProbeValidationError? _requireValidAssetName(AppcastProbeResult result) {
  final assetName = result.assetName?.trim();
  if (assetName == null || assetName.isEmpty || !assetName.toLowerCase().endsWith('.exe')) {
    return const _SilentProbeValidationError(
      code: 'invalid_asset_name',
      message: 'Silent update appcast is missing a valid installer name',
    );
  }
  return null;
}

final RegExp _sha256RegExp = RegExp(r'^[0-9a-f]{64}$');

_SilentProbeValidationError? _requireValidSha256(AppcastProbeResult result) {
  final sha256 = result.sha256?.trim().toLowerCase();
  if (sha256 == null || !_sha256RegExp.hasMatch(sha256)) {
    return const _SilentProbeValidationError(
      code: 'invalid_sha256',
      message: 'Silent update appcast is missing a valid plug:sha256 digest',
    );
  }
  return null;
}

_SilentProbeValidationError? _requireValidRolloutPercentage(AppcastProbeResult result) {
  final rolloutPercentage = result.rolloutPercentage;
  if (rolloutPercentage != null && (rolloutPercentage < 0 || rolloutPercentage > 100)) {
    return const _SilentProbeValidationError(
      code: 'invalid_rollout_percentage',
      message: 'Silent update appcast has an invalid plug:rolloutPercentage value',
    );
  }
  return null;
}
