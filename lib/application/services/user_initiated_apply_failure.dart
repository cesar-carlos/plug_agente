import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

/// Sealed root for failures produced by
/// `IAutoUpdateOrchestrator.applyAvailableUpdate`. Replaces the previous
/// magic key pattern where each non-`installerReady` outcome was packed
/// into a generic `ServerFailure`/`ConfigurationFailure` with the actual
/// reason stuffed into `Failure.context['outcome']` as a string.
///
/// The banner widget can now `switch (failure)` exhaustively instead of
/// pattern-matching strings, and any new outcome introduced in
/// [SilentUpdateOutcome] forces a new branch here (OCP-friendly).
///
/// The legacy `context['outcome']` entry is still written for backward
/// compatibility with operators inspecting persisted diagnostics; new
/// code should branch on the concrete subtype.
sealed class UserInitiatedApplyFailure extends domain.Failure {
  UserInitiatedApplyFailure.withContext({
    required super.message,
    required super.defaultCode,
    required SilentUpdateOutcome? outcome,
    super.cause,
  }) : super.withContext(
         context: <String, dynamic>{
           'operation': 'applyAvailableUpdate',
           'outcome': outcome?.name,
         },
       );

  /// Builds the concrete failure for the [outcome] returned by the
  /// silent flow. Returns the catch-all [UserInitiatedApplyCouldNotPrepare]
  /// for outcomes that should never reach this code path
  /// (`installerReady`, `requiresUserConsent`, `rolloutSkipped`, `null`).
  factory UserInitiatedApplyFailure.fromOutcome(SilentUpdateOutcome? outcome) {
    return switch (outcome) {
      SilentUpdateOutcome.cooldownActive => UserInitiatedApplyCooldownActive(),
      SilentUpdateOutcome.silentDisabled => UserInitiatedApplySilentDisabled(),
      SilentUpdateOutcome.cancelled => UserInitiatedApplyCancelled(),
      SilentUpdateOutcome.skippedByQuietHours => UserInitiatedApplyQuietHours(),
      SilentUpdateOutcome.noNewVersion => UserInitiatedApplyNoNewVersion(),
      SilentUpdateOutcome.alreadyInProgress => UserInitiatedApplyAlreadyInProgress(),
      SilentUpdateOutcome.pendingInProgress => UserInitiatedApplyPendingInProgress(),
      SilentUpdateOutcome.requiresUserConsent ||
      SilentUpdateOutcome.installerReady ||
      SilentUpdateOutcome.rolloutSkipped ||
      null => UserInitiatedApplyCouldNotPrepare(outcome: outcome),
    };
  }
}

final class UserInitiatedApplyCooldownActive extends UserInitiatedApplyFailure {
  UserInitiatedApplyCooldownActive()
    : super.withContext(
        message: 'Updates are paused after repeated failures. Try again later.',
        defaultCode: 'AUTO_UPDATE_APPLY_COOLDOWN_ACTIVE',
        outcome: SilentUpdateOutcome.cooldownActive,
      );
}

final class UserInitiatedApplySilentDisabled extends UserInitiatedApplyFailure {
  UserInitiatedApplySilentDisabled()
    : super.withContext(
        message: 'Automatic updates are disabled. Enable them in Settings to apply.',
        defaultCode: 'AUTO_UPDATE_APPLY_SILENT_DISABLED',
        outcome: SilentUpdateOutcome.silentDisabled,
      );
}

final class UserInitiatedApplyCancelled extends UserInitiatedApplyFailure {
  UserInitiatedApplyCancelled()
    : super.withContext(
        message: 'The update was cancelled before the installer was ready.',
        defaultCode: 'AUTO_UPDATE_APPLY_CANCELLED',
        outcome: SilentUpdateOutcome.cancelled,
      );
}

final class UserInitiatedApplyQuietHours extends UserInitiatedApplyFailure {
  UserInitiatedApplyQuietHours()
    : super.withContext(
        message: 'Updates are paused during quiet hours. Try again outside the window.',
        defaultCode: 'AUTO_UPDATE_APPLY_QUIET_HOURS',
        outcome: SilentUpdateOutcome.skippedByQuietHours,
      );
}

final class UserInitiatedApplyNoNewVersion extends UserInitiatedApplyFailure {
  UserInitiatedApplyNoNewVersion()
    : super.withContext(
        message: 'No new version is available right now.',
        defaultCode: 'AUTO_UPDATE_APPLY_NO_NEW_VERSION',
        outcome: SilentUpdateOutcome.noNewVersion,
      );
}

final class UserInitiatedApplyAlreadyInProgress extends UserInitiatedApplyFailure {
  UserInitiatedApplyAlreadyInProgress()
    : super.withContext(
        message: 'Another update check is still running. Try again in a moment.',
        defaultCode: 'AUTO_UPDATE_APPLY_ALREADY_IN_PROGRESS',
        outcome: SilentUpdateOutcome.alreadyInProgress,
      );
}

final class UserInitiatedApplyPendingInProgress extends UserInitiatedApplyFailure {
  UserInitiatedApplyPendingInProgress()
    : super.withContext(
        message: 'A previous update is still being applied.',
        defaultCode: 'AUTO_UPDATE_APPLY_PENDING_IN_PROGRESS',
        outcome: SilentUpdateOutcome.pendingInProgress,
      );
}

/// Catch-all for outcomes that should never reach the apply path
/// (`installerReady`, `requiresUserConsent`, `rolloutSkipped`, `null`).
/// Used so the banner has a stable failure to render instead of a
/// confusing fall-through.
final class UserInitiatedApplyCouldNotPrepare extends UserInitiatedApplyFailure {
  UserInitiatedApplyCouldNotPrepare({super.outcome})
    : super.withContext(
        message: 'Could not prepare the installer. Try again or check the diagnostics.',
        defaultCode: 'AUTO_UPDATE_APPLY_COULD_NOT_PREPARE',
      );
}
