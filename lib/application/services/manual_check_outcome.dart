/// Discriminates the success bucket of `IAutoUpdateOrchestrator.checkManual`.
///
/// Replaces the legacy `Result<bool>` shape where `true` meant "an update
/// is available" and `false` collapsed several distinct states into a
/// single bit (no update, timed out triggering the check, completion
/// timeout, circuit breaker open, etc.).
///
/// Detailed diagnostics continue to live in `UpdateCheckDiagnostics`; this
/// enum is the API-level contract for "what kind of result was this".
enum ManualCheckOutcome {
  /// Probe succeeded and the remote version is newer than the running
  /// version. Caller may surface a "update available" UI.
  updateAvailable,

  /// Probe succeeded and the remote version is not newer. Caller may
  /// surface a "up to date" UI.
  noUpdate,

  /// The WinSparkle trigger call did not return within
  /// `manualTriggerTimeout`. The check was aborted; the circuit breaker
  /// may open on repeated occurrences.
  triggerTimeout,

  /// The WinSparkle callbacks did not arrive within
  /// `manualCompletionTimeout` after the trigger succeeded. The check
  /// was aborted; diagnostics carry the technical details.
  completionTimeout,

  /// The orchestrator has not been initialised (`initialize()` was never
  /// awaited successfully or the platform does not support WinSparkle).
  notInitialized,

  /// The circuit breaker is open because of recent consecutive timeouts;
  /// caller should wait for the cooldown to expire before retrying.
  circuitOpen,

  /// Auto-update is disabled by configuration (`isAutoUpdateAvailable`
  /// returned false at the platform/runtime level). Caller should not
  /// retry until configuration changes.
  disabled;

  /// Convenience boolean preserving the legacy `Result<bool>` semantics
  /// used by older callers that only want to know "is there a new
  /// version available?".
  bool get isUpdateAvailable => this == ManualCheckOutcome.updateAvailable;
}
