/// Discriminates the success bucket of `ISilentUpdateCoordinator.checkSilently`
/// and `IAutoUpdateOrchestrator.checkSilently`.
///
/// Replaces the previous `Result<bool>` contract where `true` was overloaded
/// and `false` collapsed several distinct states into a single bit. Callers
/// that only care whether the installer is ready to apply can use
/// [isInstallerReady] as a boolean shortcut.
///
/// Rich diagnostics (channel, rollout bucket, helper SHA, etc.) continue to
/// live in `UpdateCheckDiagnostics`; this enum is the API-level contract for
/// "what kind of result was this".
enum SilentUpdateOutcome {
  /// Probe succeeded, asset validated and the installer + helper were
  /// downloaded to disk. The helper is **not** launched and the app keeps
  /// running normally; the operator must explicitly trigger the apply
  /// (via `IAutoUpdateOrchestrator.applyPendingSilentUpdate`) or close the
  /// app naturally to consume the prepared installer.
  installerReady,

  /// Probe succeeded but the remote version is not newer than the running
  /// version. No installer launched.
  noNewVersion,

  /// User disabled automatic silent updates (either before the check
  /// started or after the download but before launch). No installer launched.
  silentDisabled,

  /// Remote version exists but the configured channel or rollout bucket
  /// excludes this install. No installer launched.
  rolloutSkipped,

  /// Repeated automatic failures triggered the cooldown window. Probe was
  /// not attempted.
  cooldownActive,

  /// A pending install from a previous boot is still running (the helper
  /// has not yet terminated). No new check executed.
  pendingInProgress,

  /// Another silent check is currently in flight. The second invocation
  /// short-circuits without disturbing the running one.
  alreadyInProgress,

  /// The in-flight check was cancelled mid-flight, typically because the
  /// user disabled automatic silent updates while the download was running.
  /// No installer launched.
  cancelled,

  /// The current wall-clock time falls inside the operator-defined quiet
  /// hours window (`AUTO_UPDATE_QUIET_HOURS_START` /
  /// `AUTO_UPDATE_QUIET_HOURS_END`). Probe was skipped; the periodic timer
  /// will retry on the next cycle, and any pending install is preserved.
  skippedByQuietHours,

  /// Probe found a newer version but Windows UAC would prompt the user
  /// for elevation during install. The automatic cycle stopped before
  /// downloading. The UI surfaces an "update available, requires admin"
  /// banner; downloading and applying becomes a single user-initiated
  /// action that culminates in the UAC prompt at install time.
  requiresUserConsent;

  /// Convenience boolean for callers that only need to know "is there a
  /// downloaded installer ready to be applied?" without inspecting every
  /// variant. Note: this does **not** mean the app is closing — applying
  /// the prepared installer is now an explicit user action.
  bool get isInstallerReady => this == SilentUpdateOutcome.installerReady;
}
