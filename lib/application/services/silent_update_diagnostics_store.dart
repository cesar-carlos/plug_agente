import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';

/// Persists and hydrates automatic silent-update diagnostics through
/// [IUpdatePreferencesRepository].
class SilentUpdateDiagnosticsStore {
  SilentUpdateDiagnosticsStore({
    required IUpdatePreferencesRepository preferences,
  }) : _preferences = preferences;

  final IUpdatePreferencesRepository _preferences;

  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  void hydrate() {
    final raw = _preferences.readLastAutomaticDiagnosticsJson();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final restored = UpdateCheckDiagnostics.fromJson(decoded);
        if (restored != null) {
          lastAutomaticDiagnostics = reconcileStaleAwaitingConsent(restored);
        }
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted automatic silent update diagnostics',
        name: 'silent_update_diagnostics_store',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> clearPersisted() async {
    lastAutomaticDiagnostics = null;
    try {
      await _preferences.clearLastAutomaticDiagnosticsJson();
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to clear persisted automatic silent update diagnostics',
        name: 'silent_update_diagnostics_store',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> persist() async {
    final diagnostics = lastAutomaticDiagnostics;
    if (diagnostics == null) return;
    try {
      await _preferences.writeLastAutomaticDiagnosticsJson(jsonEncode(diagnostics.toJson()));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist automatic silent update diagnostics',
        name: 'silent_update_diagnostics_store',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Drops the [UpdateCheckCompletionSource.automaticAwaitingUserConsent]
  /// completion source when the persisted `pendingVersion` is already
  /// equal to or older than the running build.
  UpdateCheckDiagnostics reconcileStaleAwaitingConsent(UpdateCheckDiagnostics restored) {
    if (restored.completionSource != UpdateCheckCompletionSource.automaticAwaitingUserConsent) {
      return restored;
    }
    final pendingVersion = restored.pendingVersion;
    if (pendingVersion == null || pendingVersion.isEmpty) return restored;
    final comparison = AppVersionComparator.compare(AppConstants.appVersion, pendingVersion);
    if (comparison < 0) return restored;
    developer.log(
      'Dropping stale automaticAwaitingUserConsent diagnostics: '
      'persisted pendingVersion=$pendingVersion <= current=${AppConstants.appVersion}',
      name: 'silent_update_diagnostics_store',
      level: 800,
    );
    return UpdateCheckDiagnostics(
      checkedAt: restored.checkedAt,
      configuredFeedUrl: restored.configuredFeedUrl,
      requestedFeedUrl: restored.requestedFeedUrl,
      checkId: restored.checkId,
      currentVersion: AppConstants.appVersion,
      probeRequestUrl: restored.probeRequestUrl,
      triggerStartedAt: restored.triggerStartedAt,
      triggerCompletedAt: restored.triggerCompletedAt,
      completedAt: restored.completedAt,
      completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
      probeSucceeded: restored.probeSucceeded,
      appcastProbeVersion: restored.appcastProbeVersion,
      appcastProbeOs: restored.appcastProbeOs,
      appcastProbeItemCount: restored.appcastProbeItemCount,
      updateAvailable: false,
      remoteVersion: restored.remoteVersion,
      remoteDisplayVersion: restored.remoteDisplayVersion,
      assetUrl: restored.assetUrl,
      assetSize: restored.assetSize,
      assetName: restored.assetName,
      sha256: restored.sha256,
      releaseNotes: restored.releaseNotes,
      releaseNotesUrl: restored.releaseNotesUrl,
      rolloutChannel: restored.rolloutChannel,
      rolloutPercentage: restored.rolloutPercentage,
      rolloutBucket: restored.rolloutBucket,
      rolloutEligible: restored.rolloutEligible,
      automaticFailureCount: restored.automaticFailureCount,
      automaticCooldownUntil: restored.automaticCooldownUntil,
      probeMatchesSparkle: restored.probeMatchesSparkle,
    );
  }
}
