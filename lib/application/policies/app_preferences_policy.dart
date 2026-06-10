/// Pure preference rules shared by Settings UI, app shell, and boot.
abstract final class AppPreferencesPolicy {
  /// Both proactive update notifications and automatic silent updates are off.
  static bool isManualOnlyUpdateMode({
    required bool updateNotificationsEnabled,
    required bool automaticSilentUpdatesEnabled,
  }) {
    return !updateNotificationsEnabled && !automaticSilentUpdatesEnabled;
  }

  /// Whether the in-app update banner may be shown (other gates still apply).
  static bool shouldShowUpdateBanner({
    required bool updateNotificationsEnabled,
  }) {
    return updateNotificationsEnabled;
  }

  /// Whether the "start minimized" toggle is interactive in Settings.
  static bool canConfigureStartMinimized({
    required bool supportsTray,
    required bool startWithWindows,
  }) {
    return supportsTray && startWithWindows;
  }

  /// Whether the main window should open minimized at launch.
  ///
  /// Requires tray support, an autostart launch (`--autostart`), and the
  /// persisted preference enabled.
  static bool shouldStartMinimizedAtLaunch({
    required bool supportsTray,
    required bool isAutostartLaunch,
    required bool startMinimizedPreference,
  }) {
    return supportsTray && isAutostartLaunch && startMinimizedPreference;
  }

  /// Whether WinSparkle background checks should run (non-silent path).
  static bool shouldRunWinSparkleBackgroundChecks({
    required bool updateNotificationsEnabled,
    required bool automaticSilentUpdatesEnabled,
  }) {
    return !automaticSilentUpdatesEnabled && updateNotificationsEnabled;
  }
}
