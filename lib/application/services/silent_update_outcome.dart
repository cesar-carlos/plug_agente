/// Discriminates the success bucket of `ISilentUpdateCoordinator.checkSilently`
/// and `IAutoUpdateOrchestrator.checkSilently`.
///
/// Replaces the previous `Result<bool>` contract where `true` was overloaded
/// ("installer launched, app will close") and `false` collapsed several
/// distinct states into a single bit. Callers that only care whether the
/// installer started can use [isInstallerLaunched] as a boolean shortcut.
///
/// Rich diagnostics (channel, rollout bucket, helper SHA, etc.) continue to
/// live in `UpdateCheckDiagnostics`; this enum is the API-level contract for
/// "what kind of result was this".
enum SilentUpdateOutcome {
  /// Probe succeeded, asset validated, download completed, and the helper
  /// has been launched detached. The app should expect to close shortly.
  installerStarted,

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
  cancelled;

  /// Convenience boolean for callers that only need to know "should I
  /// prepare for shutdown?" without inspecting every variant.
  ///
  /// Renamed from `installerStarted` because the getter conflicted with the
  /// enum value of the same name (`conflicting_static_and_instance`).
  bool get isInstallerLaunched => this == SilentUpdateOutcome.installerStarted;
}
