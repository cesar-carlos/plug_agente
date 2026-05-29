import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:result_dart/result_dart.dart';

abstract class IAutoUpdateOrchestrator {
  bool get isAvailable;
  bool get automaticSilentUpdatesEnabled;

  /// `true` while a silent update download/install cycle is in progress.
  /// Useful for the UI to show a progress indicator without polling.
  bool get isSilentCheckInProgress;

  /// Resolves to `true` when a silent update has finished downloading
  /// and the installer + helper are staged on disk waiting for the user
  /// to apply them. The agent stays fully connected and operational
  /// while this is `true`. Async because verifying the on-disk
  /// artifacts is now done through an injectable file-system reader
  /// instead of blocking `existsSync` calls on the event loop.
  Future<bool> get hasPendingDownloadedUpdate;

  /// `true` when the silent flow detected a newer version but stopped
  /// before downloading because Windows UAC would prompt the user for
  /// elevation. The UI shows a different banner whose action triggers
  /// [applyAvailableUpdate] (download + apply in one shot).
  bool get hasUpdateAwaitingUserConsent;

  /// Broadcasts a `void` event whenever the silent update state surface
  /// changes (download finished, ready to apply, apply triggered, etc.).
  /// UI layers can listen to this stream to drive the in-app "update
  /// ready" banner without polling. The stream is broadcast so multiple
  /// listeners can subscribe; events are coalesced — listeners must re-read
  /// the orchestrator state on each tick rather than relying on event
  /// payloads.
  Stream<void> get changes;

  UpdateCheckDiagnostics? get lastManualDiagnostics;
  UpdateCheckDiagnostics? get lastBackgroundDiagnostics;
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics;

  Future<void> initialize();

  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled);

  Future<void> startAutomaticChecks();

  Future<void> checkInBackground();

  /// Triggers a silent update cycle. The success bucket carries the
  /// [SilentUpdateOutcome] discriminator so callers can distinguish
  /// "installer ready to apply" from "no new version", "rollout skipped",
  /// "cooldown active", "cancelled", etc.
  Future<Result<SilentUpdateOutcome>> checkSilently();

  /// Triggers a WinSparkle-driven manual check. The success bucket reports
  /// `true` when WinSparkle found an update and `false` when the remote
  /// reports up-to-date.
  Future<Result<ManualCheckOutcome>> checkManual();

  /// Applies a previously prepared silent update: launches the helper
  /// process and triggers the application close so the helper can run
  /// the installer. The agent only goes offline at this point — never
  /// implicitly during download.
  ///
  /// [noticeTitle] and [noticeBody] override the pre-close toast
  /// notification text; pass localized strings when calling from the UI.
  /// Returns `Failure` when no prepared update is available.
  ///
  /// Set [triggerAppClose] to `false` when invoking from a shutdown
  /// handler that is already closing the app — the helper still
  /// PID-watches the process but the close callback is skipped to avoid
  /// recursing into the shutdown sequence.
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  });

  /// Runs the full silent download + apply cycle in one shot, bypassing
  /// the UAC gate that blocks the automatic flow. Use this from the
  /// in-app banner when [hasUpdateAwaitingUserConsent] is `true`: the
  /// operator's explicit click is the consent we need. The method
  /// downloads the installer, stages the helper, and then immediately
  /// invokes the apply step so the user only confirms once (during the
  /// Windows UAC prompt at install time).
  ///
  /// [noticeTitle] and [noticeBody] are forwarded to the pre-close toast
  /// (same contract as [applyPendingSilentUpdate]). Returns `Failure`
  /// when no update is available, the download fails, or the helper
  /// launch fails.
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  });
}
