class AppSettingsKeys {
  AppSettingsKeys._();

  static const String isDarkModeEnabled = 'settings.is_dark_mode_enabled';
  static const String startWithWindows = 'settings.start_with_windows';
  static const String startMinimized = 'settings.start_minimized';
  static const String minimizeToTray = 'settings.minimize_to_tray';
  static const String closeToTray = 'settings.close_to_tray';
  static const String automaticSilentUpdatesEnabled = 'settings.automatic_silent_updates_enabled';

  /// When false, staged silent updates are not applied automatically after
  /// download; the operator must confirm via the in-app banner or wait for
  /// natural app shutdown. Defaults to enabled.
  static const String automaticSilentUpdatesAutoApplyEnabled =
      'settings.automatic_silent_updates_auto_apply_enabled';

  /// When false, hides proactive update UI (in-app banner) and disables
  /// WinSparkle background checks while automatic silent updates are off.
  /// Manual checks from Settings remain available.
  static const String updateNotificationsEnabled = 'settings.update_notifications_enabled';

  /// Persists the operator's "remind me later" gesture for the in-app
  /// auto-update banner. Stored as a JSON object with the pending
  /// version that was dismissed and the wall-clock timestamp until
  /// which the banner stays hidden. The banner re-appears if the
  /// stored version changes (a newer build was found) or the TTL
  /// expires.
  static const String autoUpdateBannerDismiss = 'settings.auto_update_banner_dismiss';
}
