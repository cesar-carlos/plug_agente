/// Shared default values for the auto-update flow. Centralised so the
/// orchestrator and the coordinator agree on the same numbers without
/// either side leaking implementation constants to the other through a
/// "public alias" workaround.
///
/// Kept as a `abstract final class` rather than a top-level constant
/// group so tests/operators discover the values via auto-complete and
/// rules can rename without breaking call sites that use
/// `AutoUpdateDefaults.x` style references.
abstract final class AutoUpdateDefaults {
  /// Number of consecutive failures before the automatic silent flow
  /// enters its cooldown window.
  static const int automaticFailureCooldownThreshold = 3;

  /// How long the automatic silent flow stays paused once the failure
  /// counter crosses [automaticFailureCooldownThreshold].
  static const Duration automaticFailureCooldown = Duration(hours: 6);

  /// Maximum wall-clock window during which the reconciler treats a
  /// *launched* helper as still running. Past this point a launched pending
  /// record is marked failed instead of kept alive. Staged-only downloads
  /// (no launch evidence) are unaffected.
  static const Duration helperWaitDuration = Duration(minutes: 30);

  /// Maximum age for a staged (downloaded, not launched) pending update.
  /// Past this ops bound the record and artifacts are cleared so Ready does
  /// not linger indefinitely when the feed moves on or the user never applies.
  static const Duration stagedPendingTtl = Duration(days: 7);
}
