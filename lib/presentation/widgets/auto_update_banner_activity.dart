/// Sealed activity used by the in-app silent update banner. Replaces the
/// previous pair of `bool _isApplying` + `enum _ApplyPhase` that always
/// travelled together with implicit invariants (`idle ↔ !_isApplying`).
///
/// Pattern matching is exhaustive so adding a new phase forces both the
/// state transitions and the rendered label to be updated together.
sealed class AutoUpdateBannerActivity {
  const AutoUpdateBannerActivity();

  /// Convenience accessor used by buttons to disable input while an
  /// apply is running. Idle is the only case that allows interaction.
  bool get isBusy => this is! AutoUpdateBannerIdle;
}

/// Banner is showing the call-to-action buttons; no work in flight.
final class AutoUpdateBannerIdle extends AutoUpdateBannerActivity {
  const AutoUpdateBannerIdle();
}

/// Downloading the installer because the cycle started from the UAC
/// "awaiting consent" path (no bytes were staged before the user clicked).
final class AutoUpdateBannerDownloading extends AutoUpdateBannerActivity {
  const AutoUpdateBannerDownloading();
}

/// Staging the helper / writing artifacts. Used both as the initial
/// state for the pending-downloaded path (bytes are already on disk —
/// nothing to download) and as the bridge step in the awaiting-consent
/// path between download and launch.
final class AutoUpdateBannerStaging extends AutoUpdateBannerActivity {
  const AutoUpdateBannerStaging();
}

/// Helper process was launched; the app close is in flight. The banner
/// stays in this state until the platform terminates the process.
final class AutoUpdateBannerLaunching extends AutoUpdateBannerActivity {
  const AutoUpdateBannerLaunching();
}
