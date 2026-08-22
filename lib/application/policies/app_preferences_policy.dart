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

  /// Whether the main window should stay hidden after desktop shell bootstrap.
  ///
  /// Login launches (`--autostart`) stay in the tray whenever tray is available.
  /// Manual launches always show the window.
  static bool shouldStartMinimizedAtLaunch({
    required bool supportsTray,
    required bool isAutostartLaunch,
  }) {
    return supportsTray && isAutostartLaunch;
  }

  /// Autostart keeps the window hidden while tray/window managers initialize
  /// so login never flashes a frame before Dart decides visibility.
  static bool shouldHideWindowDuringAutostartBootstrap({
    required bool isAutostartLaunch,
  }) {
    return isAutostartLaunch;
  }

  /// Login launches stay in the tray after bootstrap. Manual launches never
  /// use this reveal path.
  static bool shouldRevealWindowAfterAutostartBootstrap({
    required bool isAutostartLaunch,
  }) {
    return !isAutostartLaunch && isAutostartLaunch;
  }

  /// Whether WinSparkle background checks should run (non-silent path).
  static bool shouldRunWinSparkleBackgroundChecks({
    required bool updateNotificationsEnabled,
    required bool automaticSilentUpdatesEnabled,
  }) {
    return !automaticSilentUpdatesEnabled && updateNotificationsEnabled;
  }
}
